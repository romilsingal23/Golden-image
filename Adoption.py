import os
import io
import json
import logging
import requests
import pandas as pd
from loguru import logger
from datetime import datetime
from google.cloud import storage
from google.cloud import compute_v1
from google.cloud import secretmanager
from google.cloud import resourcemanager_v3

TENANT_ID = os.getenv('TENANT_ID')
X_API_KEY_VALUE = os.getenv('X_API_KEY')
CAT_TABLE_URL = os.getenv('CAT_TABLE_URL')
AUTHORITY_URL = os.getenv('AUTHORITY_URL')
CLIENT_ID = os.getenv('CLIENT_ID')
CLIENT_SECRET_NAME = os.getenv('CLIENT_SECRET_NAME')
GRAPH_API_SCOPE_URL = os.getenv('GRAPH_API_SCOPE_URL')
GRAPH_API_USERS_URL = os.getenv('GRAPH_API_USERS_URL')
project_id = os.getenv('PROJECT_ID')
organization_id = os.getenv('ORGANIZATION_ID', "531591688136")
bucket_name = os.getenv('BUCKET_NAME') 

def list_projects_in_organization(org_id):
    projects_client = resourcemanager_v3.ProjectsClient()
    folders_client = resourcemanager_v3.FoldersClient()
    folders = folders_client.search_folders(request={"query": f"parent=organizations/{org_id}"})
    all_projects = []
    for folder in folders:
        all_projects.extend(fetch_projects_in_folder(folder.name, folders_client, projects_client))
    logger.info(f"len projects: {len(all_projects)}")
    return all_projects

def fetch_projects_in_folder(folder_id, folders_client, projects_client):
    projects = []
    for project in projects_client.list_projects(parent=folder_id):
        if project.state.name == "ACTIVE":
            projects.append(project.project_id)
    subfolders = folders_client.list_folders(parent=folder_id)
    for subfolder in subfolders:
        projects.extend(fetch_projects_in_folder(subfolder.name, folders_client, projects_client))
    return projects

def call_api_with_batch_get(account_ids, x_api_key, cat_table_url):
    exceptions = []
    try:
        # logic to call the API with batch get
        auth_headers = {'X-API-KEY': x_api_key}
        payload = {
            "batch_get": {
                "query": {
                    "GCP": account_ids,
                }
            }
        }
        
        response = requests.post(cat_table_url, headers=auth_headers, json=payload)
        payload = response.json()
        filtered_data = []
        for item in payload['queryResults']['Items']:
            filtered_item = { 'askid': item.get('ask_id'), 'msid': item.get('owner_msid')
            , 'subscription_id': item.get('account_id'), 'employeeid': item.get('employee_id')}
            filtered_data.append(filtered_item)
        return filtered_data
    except Exception as e:
        logging.error(
            'Error in getting ASKids and MSids ids from api endpoint\'%s\':', e)
        exceptions.append(e)
        return exceptions

def get_secret_gcp(secret_id):
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

def get_email_ids_from_employeeIds(employee_ids):
        exceptions = []
        try:
            client_id = get_secret_gcp(CLIENT_ID)
            responce_client_secret = get_secret_gcp(CLIENT_SECRET_NAME)
            tenant_id = get_secret_gcp(TENANT_ID)
            authority_url = AUTHORITY_URL.format(tenant_id)
            request_data = {
                'grant_type': 'client_credentials',
                'client_id': client_id,
                'client_secret': responce_client_secret,
                'scope': GRAPH_API_SCOPE_URL
            }
            headers = {'Content-type': 'application/x-www-form-urlencoded'}
            # Get access token
            response = requests.post(authority_url, headers=headers, data=request_data)
            filtered_response = {}
                    
            if employee_ids and len(employee_ids) > 0 and response.status_code == 200:
                employeeid_chunks = [employee_ids[x:x+15] for x in range(0, len(employee_ids), 15)]
                for empidschunk in employeeid_chunks:
                    filter_string = ','.join(["'{}'".format(empId) for empId in empidschunk])
                    graph_api_url = f'{GRAPH_API_USERS_URL}?$filter=employeeId in ({filter_string})&$select=mail,employeeId'
                    headers = {
                        'Accept': 'application/json',
                        'Authorization': 'Bearer {}'.format(response.json()['access_token'])
                    }
                    # Get email data
                    users_response = requests.get(graph_api_url, headers=headers)
                    if users_response.status_code == 200:
                        users = users_response.json().get('value')
                        response_data_by_employeeid = {}
                        for user in users:
                            employee_group = user.get('employeeId')
                            if employee_group not in response_data_by_employeeid:
                                response_data_by_employeeid[employee_group] = user.get('mail')
                        filtered_response.update(response_data_by_employeeid)
                    else:
                        exceptions.append(response.text)
                        return exceptions
            return filtered_response
 
        except Exception as e:
            logging.error("Error while getting email ids from graph api: %s",e)
            exceptions.append(e)
            return exceptions

def fetch_instance_data(org_project_id):   
    instance_client = compute_v1.InstancesClient()
    disk_client = compute_v1.DisksClient()
    image_client = compute_v1.ImagesClient()
    results = []
    account_ids = []

    request = compute_v1.AggregatedListInstancesRequest(project=org_project_id, max_results=300)
    while True:
        all_instances = instance_client.aggregated_list(request=request) 
        for zone, instances_scoped_list in all_instances:
            if instances_scoped_list.instances:
                for instance in instances_scoped_list.instances:
                    instance_name = instance.name
                    vm_creation_time = instance.creation_timestamp  # VM creation timestamp
                    vm_zone = zone.split('/')[-1]  # Extract zone from the zone path
                    
                    # Iterate through attached disks
                    for disk in instance.disks:
                        disk_source = disk.source
                        
                        if not disk_source:
                            continue
                        
                        # Extract disk name and zone
                        disk_name = disk_source.split("/")[-1]
                        disk_zone = disk_source.split("/all_instances/")[1].split("/")[0]
                        
                        # Fetch the source image URL from the disk
                        try:
                            disk_info = disk_client.get(project=org_project_id, zone=disk_zone, disk=disk_name)
                            source_image_url = disk_info.source_image
                        except Exception as e:
                            logger.info(f"Error fetching disk info for {disk_name}: {e}")
                            continue
                        
                        if source_image_url:
                            # Extract image name and project from the source image URL
                            image_name = source_image_url.split("/")[-1]
                            image_project = source_image_url.split("/")[-4]
                            
                            # Fetch image labels and creation timestamp
                            try:
                                image_info = image_client.get(project=image_project, image=image_name)
                                labels = dict(image_info.labels) if image_info.labels else {}
                                deprecation_status = image_info.deprecated
                                image_creation_time = image_info.creation_timestamp  # Image creation timestamp
                            except Exception as e:
                                logger.info(f"Error fetching image info for {image_name}: {e}")
                                labels = {}
                                deprecation_status = None
                                image_creation_time = None
                            
                            # Determine compliance status
                            compliant_status = "NON_COMPLIANT"
                            if labels and 'image_type' in labels:
                                if labels['image_type'] == 'golden-image':
                                    compliant_status = "COMPLIANT"
                            if deprecation_status: 
                                deprecation_status = deprecation_status.state
                            
                            account_ids.append(org_project_id)
                            # Store the result
                            results.append({
                                "Project": org_project_id,
                                "VM Name": instance_name,
                                "VM Creation Time": vm_creation_time,
                                "VM Zone": vm_zone,
                                "Source Image": image_name,
                                "Image Creation Time": image_creation_time,
                                "Labels": json.dumps(labels),
                                "Compliant Status": compliant_status,
                                "Deprecation Status": deprecation_status,
                            })
                        else:
                            logger.info(f"No source image found for disk {disk_name} in project {org_project_id}")
    
        if all_instances.next_page_token:
            request.page_token = all_instances.next_page_token
        else:
            break

    unique_account_ids = (list(set(account_ids)))
    X_API_KEY = get_secret_gcp(X_API_KEY_VALUE)
    result_json_array = call_api_with_batch_get(unique_account_ids,X_API_KEY,CAT_TABLE_URL)
    
    # Populate the dictionary with data from the second array which has askid and msid attached
    employee_ids = []
    subscription_mapping = {}
    for obj in result_json_array:
        if obj["employeeid"]:
            employee_ids.append(obj.get("employeeid"))
            subscription_mapping[obj["subscription_id"]] = {"askid": obj["askid"], "msid": obj["msid"], "employeeid": obj["employeeid"]}
    # Iterate through the original array without ask ID & msid and map the respective ask ID and msid to account_id
    for obj in results:
        subscription_id = obj["Project"]
        if subscription_id in subscription_mapping:
            obj["askid"] = subscription_mapping[subscription_id]["askid"]
            obj["msid"] = subscription_mapping[subscription_id]["msid"]
            obj["employeeid"] = str(subscription_mapping[subscription_id]["employeeid"])
    data = results
    try:
        # Get unique employee ids
        unique_employee_ids = (list(set(employee_ids)))
        user_email_response = get_email_ids_from_employeeIds(unique_employee_ids)
        results = [{**obj, **{'email': user_email_response.get(obj.get('employeeid'))}} for obj in data]
        logging.info('Result with email: %s', len(results))
    except Exception as e:
        logging.error('Error in getting User Email \'%s\':', e)
    return results

def upload_to_gcs(bucket_name, destination_blob_name, buffer):
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
        success_list, failure_list = [], []
        all_results = []

        for org_project_id in projects:
            try:
                logger.info(f"Processing Project: {org_project_id}")
                project_data = fetch_instance_data(org_project_id)
                all_results.extend(project_data)
                success_list.append(org_project_id)
            except Exception as e:
                failure_list.append(org_project_id)
                # Log the error and continue to the next project
                logger.error(f"Error processing project {org_project_id}: {e}")
                continue
        logger.info(f"Success Project List: {success_list}")
        logger.info(f"Failure Project List: {failure_list}")
        logger.info(f"Success Project Count: {len(success_list)}")
        logger.info(f"Failure Project Count: {len(failure_list)}")

        # Convert results to a DataFrame and save to Excel
        if all_results:
            df = pd.DataFrame(all_results)
            buffer = io.BytesIO()
            df.to_excel(buffer, index=False)
            buffer.seek(0)

            cur_date = datetime.now().strftime("%Y-%m-%d")
            upload_to_gcs(bucket_name, f"adoption-report-{cur_date}.xlsx", buffer)
            logger.info("File uploaded successfully!")
            return {"message": "File uploaded successfully!"}, 200
        else:
            logger.warning("No results to process. Exiting.")
            return {"message": "No data processed"}, 204

    except Exception as e:
        logger.error(f"Error in main function: {e}")
        return {"error": str(e)}, 500

if __name__ == "__main__":
    main()
