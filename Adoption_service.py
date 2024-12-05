import os
import json
import logging
import requests
from google.cloud import compute_v1
from google.cloud import secretmanager
from google.cloud import resourcemanager_v3
from google.cloud import storage

TENANT_ID = os.getenv('TENANT_ID', "db05faca-c82a-4b9d-b9c5-0f64b6755421")
X_API_KEY_VALUE = os.getenv('X_API_KEY', "x-api-key")
CAT_TABLE_URL = os.getenv('CAT_TABLE_URL', "https://tp8e3wgfo2.execute-api.us-east-1.amazonaws.com/v1/accounts/batchget")
AUTHORITY_URL = os.getenv('AUTHORITY_URL', "https://login.microsoftonline.com/{}/oauth2/v2.0/token")
CLIENT_ID = os.getenv('CLIENT_ID', "client-id")
CLIENT_SECRET_NAME = os.getenv('CLIENT_SECRET_NAME', "client-secret")
GRAPH_API_SCOPE_URL = os.getenv('GRAPH_API_SCOPE_URL', "https://graph.microsoft.com/.default")
GRAPH_API_USERS_URL = os.getenv('GRAPH_API_USERS_URL', "https://graph.microsoft.com/v1.0/users")
PROJECT_ID = os.getenv('PROJECT_ID', "your-gcp-project-id")

def fetch_projects():
    """Fetch all projects the service account has access to using the Resource Manager API."""
    client = resourcemanager_v3.ProjectsClient()
    projects = []

    for project in client.list_projects():
        if project.state == resourcemanager_v3.Project.State.ACTIVE:
            projects.append(project.project_id)
    
    return projects

def call_api_with_batch_get(account_ids, x_api_key, cat_table_url):
    """Call API with batch get to fetch additional data like MSID and employee ID."""
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
        logging.error(f"Error in getting ASKids and MSids ids from API endpoint: {e}")
        return []

def get_secret_gcp(secret_id):
    """Fetch secret from GCP Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

def get_email_ids_from_employee_ids(employee_ids):
    """Get email IDs based on employee IDs using Microsoft Graph API."""
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

        if response.status_code == 200 and employee_ids:
            employeeid_chunks = [employee_ids[x:x + 15] for x in range(0, len(employee_ids), 15)]
            response_data_by_employeeid = {}
            for emp_ids_chunk in employeeid_chunks:
                filter_string = ','.join([f"'{emp_id}'" for emp_id in emp_ids_chunk])
                graph_api_url = f'{GRAPH_API_USERS_URL}?$filter=employeeId in ({filter_string})&$select=mail,employeeId'
                headers = {'Accept': 'application/json', 'Authorization': f"Bearer {response.json()['access_token']}"}
                users_response = requests.get(graph_api_url, headers=headers)

                if users_response.status_code == 200:
                    users = users_response.json().get('value')
                    for user in users:
                        employee_group = user.get('employeeId')
                        response_data_by_employeeid[employee_group] = user.get('mail')
            return response_data_by_employeeid
    except Exception as e:
        logging.error(f"Error while getting email ids from Graph API: {e}")
        return {}

def fetch_instance_data(project_ids):
    """Fetch VM and related data for all projects."""
    instance_client = compute_v1.InstancesClient()
    disk_client = compute_v1.DisksClient()
    image_client = compute_v1.ImagesClient()
    results = []

    for project_id in project_ids:
        request = compute_v1.AggregatedListInstancesRequest(project=project_id, max_results=300)

        while True:
            response = instance_client.aggregated_list(request=request)

            for zone, instances_scoped_list in response.items():
                if 'instances' in instances_scoped_list:
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
                                print(f"Error fetching disk info for {disk_name}: {e}")
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
                                    print(f"Error fetching image info for {image_name}: {e}")
                                    labels = {}
                                    deprecation_status = None
                                    image_creation_time = None

                                compliant_status = "NON_COMPLIANT"
                                if labels and 'image_type' in labels:
                                    if labels['image_type'] == 'golden-image':
                                        compliant_status = "COMPLIANT"
                                if deprecation_status:
                                    deprecation_status = deprecation_status.state

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
                            else:
                                print(f"No source image found for disk {disk_name} in project {project_id}")

            if response.next_page_token:
                request.page_token = response.next_page_token
            else:
                break

    return results

def main():
    """Main function to fetch VM data for all projects."""
    try:
        projects = fetch_projects()
        if not projects:
            print("No projects found that the service account has access to.")
            return

        # Fetch VM data for each project
        all_results = fetch_instance_data(projects)

        # Call the API with batch get
        unique_account_ids = list(set([result["Project"] for result in all_results]))
        X_API_KEY = get_secret_gcp(X_API_KEY_VALUE)
        result_json_array = call_api_with_batch_get(unique_account_ids, X_API_KEY, CAT_TABLE_URL)

        # Map the MSID and employee IDs from the API response to the VM data
        subscription_mapping = {}
        for obj in result_json_array:
            if obj["employeeid"]:
                subscription_mapping[obj["subscription_id"]] = {
                    "askid": obj["askid"],
                    "msid": obj["msid"],
                    "employeeid": obj["employeeid"]
                }

        # Add employee details to VM data
        for obj in all_results:
            subscription_id = obj["Project"]
            if subscription_id in subscription_mapping:
                obj["askid"] = subscription_mapping[subscription_id]["askid"]
                obj["msid"] = subscription_mapping[subscription_id]["msid"]
                obj["employeeid"] = subscription_mapping[subscription_id]["employeeid"]

        # Convert results to DataFrame and print/export
        df = pd.DataFrame(all_results)
        df.to_csv('vm_data.csv', index=False)
        print("VM Data exported to vm_data.csv")

    except Exception as e:
        logging.error(f"Error in main function: {e}")

if __name__ == "__main__":
    main()
