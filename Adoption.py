import os
import io
import json
import logging
import requests
import pandas as pd
from loguru import logger
from google.cloud import storage
from google.cloud import compute_v1
from google.cloud import secretmanager

TENANT_ID = os.getenv('TENANT_ID', "db05faca-c82a-4b9d-b9c5-0f64b6755421")
X_API_KEY_VALUE = os.getenv('X_API_KEY', "x-api-key")
CAT_TABLE_URL = os.getenv('CAT_TABLE_URL', "https://tp8e3wgfo2.execute-api.us-east-1.amazonaws.com/v1/accounts/batchget")
AUTHORITY_URL = os.getenv('AUTHORITY_URL', "https://login.microsoftonline.com/{}/oauth2/v2.0/token")
CLIENT_ID = os.getenv('CLIENT_ID', "client-id")
CLIENT_SECRET_NAME = os.getenv('CLIENT_SECRET_NAME', "client-secret")
GRAPH_API_SCOPE_URL = os.getenv('GRAPH_API_SCOPE_URL', "https://graph.microsoft.com/.default")
GRAPH_API_USERS_URL = os.getenv('GRAPH_API_USERS_URL', "https://graph.microsoft.com/v1.0/users")
project_id = os.getenv('PROJECT_ID', "zjmqcnnb-gf42-i38m-a28a-y3gmil")  # Google Cloud Project ID

def call_api_with_batch_get(account_ids, x_api_key, cat_table_url):
    try:
        auth_headers = {'X-API-KEY': x_api_key}
        payload = {
            "batch_get": {
                "query": {
                    "GCP": account_ids,
                }
            }
        }
        response = requests.post(cat_table_url, headers=auth_headers, json=payload)
        response.raise_for_status()
        payload = response.json()
        filtered_data = []
        for item in payload['queryResults']['Items']:
            filtered_item = {
                'askid': item.get('ask_id'),
                'msid': item.get('owner_msid'),
                'subscription_id': item.get('account_id'),
                'employeeid': item.get('employee_id')
            }
            filtered_data.append(filtered_item)
        return filtered_data
    except Exception as e:
        logging.error('Error in call_api_with_batch_get: %s', e)
        raise e

def get_secret_gcp(secret_id):
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        logging.error('Error in get_secret_gcp: %s', e)
        raise e

def get_email_ids_from_employeeIds(employee_ids):
    try:
        client_id = get_secret_gcp(CLIENT_ID)
        client_secret = get_secret_gcp(CLIENT_SECRET_NAME)
        authority_url = AUTHORITY_URL.format(TENANT_ID)
        request_data = {
            'grant_type': 'client_credentials',
            'client_id': client_id,
            'client_secret': client_secret,
            'scope': GRAPH_API_SCOPE_URL
        }
        headers = {'Content-type': 'application/x-www-form-urlencoded'}
        response = requests.post(authority_url, headers=headers, data=request_data)
        response.raise_for_status()
        access_token = response.json().get('access_token')

        filtered_response = {}
        if employee_ids:
            employeeid_chunks = [employee_ids[x:x+15] for x in range(0, len(employee_ids), 15)]
            for chunk in employeeid_chunks:
                filter_string = ','.join([f"'{emp_id}'" for emp_id in chunk])
                graph_api_url = f"{GRAPH_API_USERS_URL}?$filter=employeeId in ({filter_string})&$select=mail,employeeId"
                headers = {'Authorization': f'Bearer {access_token}'}
                users_response = requests.get(graph_api_url, headers=headers)
                users_response.raise_for_status()
                users = users_response.json().get('value', [])
                for user in users:
                    filtered_response[user.get('employeeId')] = user.get('mail')
        return filtered_response
    except Exception as e:
        logging.error('Error in get_email_ids_from_employeeIds: %s', e)
        raise e

def fetch_instance_data(project_id):
    try:
        instance_client = compute_v1.InstancesClient()
        disk_client = compute_v1.DisksClient()
        image_client = compute_v1.ImagesClient()
        results = []
        account_ids = []

        request = compute_v1.AggregatedListInstancesRequest(project=project_id)
        zones = instance_client.aggregated_list(request=request)

        for zone, instances_scoped_list in zones:
            if instances_scoped_list.instances:
                for instance in instances_scoped_list.instances:
                    instance_name = instance.name
                    vm_creation_time = instance.creation_timestamp
                    vm_zone = zone.split('/')[-1]
                    for disk in instance.disks:
                        disk_source = disk.source
                        if disk_source:
                            disk_name = disk_source.split("/")[-1]
                            disk_zone = disk_source.split("/zones/")[1].split("/")[0]
                            try:
                                disk_info = disk_client.get(project=project_id, zone=disk_zone, disk=disk_name)
                                source_image_url = disk_info.source_image
                            except Exception:
                                continue

                            if source_image_url:
                                image_name = source_image_url.split("/")[-1]
                                image_project = source_image_url.split("/")[-4]
                                try:
                                    image_info = image_client.get(project=image_project, image=image_name)
                                    labels = dict(image_info.labels) if image_info.labels else {}
                                    compliant_status = "COMPLIANT" if labels.get('image_type') == 'golden-image' else "NON_COMPLIANT"
                                except Exception:
                                    continue

                                results.append({
                                    "Project": project_id,
                                    "VM Name": instance_name,
                                    "VM Creation Time": vm_creation_time,
                                    "VM Zone": vm_zone,
                                    "Source Image": image_name,
                                    "Labels": json.dumps(labels),
                                    "Compliant Status": compliant_status
                                })

        return results
    except Exception as e:
        logging.error('Error in fetch_instance_data: %s', e)
        raise e

def upload_to_gcs(buffer, bucket_name, destination_blob_name):
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        blob.upload_from_file(buffer, content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        print(f"File uploaded to gs://{bucket_name}/{destination_blob_name}")
    except Exception as e:
        logging.error('Error in upload_to_gcs: %s', e)
        raise e

def main(request):
    try:
        projects = ["zjmqcnnb-gf42-i38m-a28a-y3gmil"]
        bucket_name = "rsingal-gcp-build-bucket"
        output_file = "vm_image_labels.xlsx"

        all_results = []
        for project in projects:
            project_data = fetch_instance_data(project)
            all_results.extend(project_data)

        df = pd.DataFrame(all_results)
        buffer = io.BytesIO()
        df.to_excel(buffer, index=False)
        buffer.seek(0)
        upload_to_gcs(buffer, bucket_name, output_file)

        return {"message": "File uploaded successfully!"}, 200
    except Exception as e:
        logging.error("Error in main function: %s", e)
        return {"error": str(e)}, 500
