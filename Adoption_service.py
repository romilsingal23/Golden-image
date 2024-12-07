import os
import io
import json
import logging
import requests
import pandas as pd
from loguru import logger
from google.cloud import storage, secretmanager, resource_manager_v3, compute_v1

TENANT_ID = os.getenv('TENANT_ID')
X_API_KEY_VALUE = os.getenv('X_API_KEY')
CAT_TABLE_URL = os.getenv('CAT_TABLE_URL')
AUTHORITY_URL = os.getenv('AUTHORITY_URL')
CLIENT_ID = os.getenv('CLIENT_ID')
CLIENT_SECRET_NAME = os.getenv('CLIENT_SECRET_NAME')
GRAPH_API_SCOPE_URL = os.getenv('GRAPH_API_SCOPE_URL')
GRAPH_API_USERS_URL = os.getenv('GRAPH_API_USERS_URL')
organization_id = os.getenv('ORGANIZATION_ID')
bucket_name = os.getenv('BUCKET_NAME')


def call_api_with_batch_get(account_ids, x_api_key, cat_table_url):
    exceptions = []
    try:
        auth_headers = {'X-API-KEY': x_api_key}
        payload = {"batch_get": {"query": {"GCP": account_ids}}}
        response = requests.post(cat_table_url, headers=auth_headers, json=payload)
        payload = response.json()
        filtered_data = []
        for item in payload['queryResults']['Items']:
            filtered_item = {
                'askid': item.get('ask_id'),
                'msid': item.get('owner_msid'),
                'subscription_id': item.get('account_id'),
                'employeeid': item.get('employee_id'),
            }
            filtered_data.append(filtered_item)
        return filtered_data
    except Exception as e:
        logging.error("Error fetching data from API: %s", e)
        exceptions.append(e)
        return exceptions


def get_secret_gcp(secret_id):
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{organization_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")


def get_email_ids_from_employee_ids(employee_ids):
    exceptions = []
    try:
        client_id = get_secret_gcp(CLIENT_ID)
        client_secret = get_secret_gcp(CLIENT_SECRET_NAME)
        tenant_id = get_secret_gcp(TENANT_ID)
        authority_url = AUTHORITY_URL.format(tenant_id)
        request_data = {
            'grant_type': 'client_credentials',
            'client_id': client_id,
            'client_secret': client_secret,
            'scope': GRAPH_API_SCOPE_URL,
        }
        headers = {'Content-type': 'application/x-www-form-urlencoded'}
        response = requests.post(authority_url, headers=headers, data=request_data)
        filtered_response = {}

        if employee_ids and response.status_code == 200:
            employee_chunks = [employee_ids[x:x+15] for x in range(0, len(employee_ids), 15)]
            for chunk in employee_chunks:
                filter_string = ','.join(f"'{emp}'" for emp in chunk)
                graph_api_url = f"{GRAPH_API_USERS_URL}?$filter=employeeId in ({filter_string})&$select=mail,employeeId"
                headers['Authorization'] = f"Bearer {response.json()['access_token']}"
                users_response = requests.get(graph_api_url, headers=headers)
                if users_response.status_code == 200:
                    for user in users_response.json().get('value', []):
                        filtered_response[user.get('employeeId')] = user.get('mail')
                else:
                    exceptions.append(users_response.text)
        return filtered_response
    except Exception as e:
        logging.error("Error fetching email IDs: %s", e)
        exceptions.append(e)
        return exceptions


def list_projects_in_organization(org_id):
    client = resource_manager_v3.ProjectsClient()
    request = resource_manager_v3.SearchProjectsRequest(query=f"parent.type:organization parent.id:{org_id}")
    return [project.project_id for project in client.search_projects(request=request) if project.state.name == "ACTIVE"]


def fetch_instance_data(project_id):
    instance_client = compute_v1.InstancesClient()
    disk_client = compute_v1.DisksClient()
    image_client = compute_v1.ImagesClient()
    results = []
    account_ids = []

    request = compute_v1.AggregatedListInstancesRequest(project=project_id, max_results=300)
    while True:
        zones = instance_client.aggregated_list(request=request)
        for zone, instances_scoped_list in zones:
            if instances_scoped_list.instances:
                for instance in instances_scoped_list.instances:
                    instance_name = instance.name
                    vm_creation_time = instance.creation_timestamp
                    vm_zone = zone.split('/')[-1]

                    for disk in instance.disks:
                        disk_source = disk.source
                        if not disk_source:
                            continue

                        disk_name = disk_source.split("/")[-1]
                        disk_zone = disk_source.split("/zones/")[1].split("/")[0]

                        try:
                            disk_info = disk_client.get(project=project_id, zone=disk_zone, disk=disk_name)
                            source_image_url = disk_info.source_image
                        except Exception as e:
                            logger.info(f"Error fetching disk info for {disk_name}: {e}")
                            continue

                        if source_image_url:
                            image_name = source_image_url.split("/")[-1]
                            image_project = source_image_url.split("/")[-4]
                            try:
                                image_info = image_client.get(project=image_project, image=image_name)
                                labels = dict(image_info.labels) if image_info.labels else {}
                                deprecation_status = image_info.deprecated
                                image_creation_time = image_info.creation_timestamp
                            except Exception as e:
                                logger.info(f"Error fetching image info for {image_name}: {e}")
                                labels, deprecation_status, image_creation_time = {}, None, None

                            compliant_status = "COMPLIANT" if labels.get('image_type') == 'golden-image' else "NON_COMPLIANT"
                            if deprecation_status:
                                deprecation_status = deprecation_status.state

                            account_ids.append(project_id)
                            results.append({
                                "Project": project_id,
                                "VM Name": instance_name,
                                "VM Creation Time": vm_creation_time,
                                "VM Zone": vm_zone,
                                "Source Image": image_name,
                                "Image Creation Time": image_creation_time,
                                "Labels": json.dumps(labels),
                                "Compliant Status": compliant_status,
                                "Deprecation Status": deprecation_status,
                            })

        if zones.next_page_token:
            request.page_token = zones.next_page_token
        else:
            break

    X_API_KEY = get_secret_gcp(X_API_KEY_VALUE)
    result_json_array = call_api_with_batch_get(list(set(account_ids)), X_API_KEY, CAT_TABLE_URL)
    employee_ids, subscription_mapping = [], {}
    for obj in result_json_array:
        if obj["employeeid"]:
            employee_ids.append(obj["employeeid"])
            subscription_mapping[obj["subscription_id"]] = obj

    for obj in results:
        if obj["Project"] in subscription_mapping:
            obj.update(subscription_mapping[obj["Project"]])

    return results, list(set(employee_ids))


def upload_to_gcs(file_path, bucket_name, destination_blob_name, buffer):
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        blob.upload_from_file(buffer, content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        logger.info(f"File uploaded to gs://{bucket_name}/{destination_blob_name}")
    except Exception as e:
        logger.info(f"Error uploading file to GCS: {e}")


def main(request=None):
    try:
        projects = list_projects_in_organization(organization_id)
        all_results, all_employee_ids = [], []

        for project in projects:
            logger.info(f"Processing Project: {project}")
            project_data, employee_ids = fetch_instance_data(project)
            all_results.extend(project_data)
            all_employee_ids.extend(employee_ids)

        unique_employee_ids = list(set(all_employee_ids))
        user_email_response = get_email_ids_from_employee_ids(unique_employee_ids)
        for obj in all_results:
            obj["email"] = user_email_response.get(obj.get("employeeid"))

        df = pd.DataFrame(all_results)
        buffer = io.BytesIO()
        df.to_excel(buffer, index=False)
        buffer.seek(0)

        upload_to_gcs("vm_image_labels.xlsx", bucket_name, "vm_image_labels.xlsx", buffer)
        return {"message": "File uploaded successfully!"}, 200
    except Exception as e:
        logging.error("Error in main function: %s", e)
        return {"error": str(e)}, 500


if __name__ == "__main__":
    main()
