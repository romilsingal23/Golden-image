import os
import json
import pytz
import time
import logging
import traceback
from google.cloud import compute_v1
from datetime import datetime, timezone, timedelta

# Initialize logging
logger = logging.getLogger()
logging.basicConfig(level=logging.INFO)

zone = 'us-east1-b'
delete_interval = 1
project_id = os.getenv('PROJECT_ID')  # Google Cloud Project ID

def list_instances(project_id, zone):
    instance_client = compute_v1.InstancesClient()
    request = compute_v1.ListInstancesRequest(project=project_id, zone=zone)
    instances = []

    while True:
        response = instance_client.list(request=request)
        instances.extend(response.items)
        if response.next_page_token:
            request.page_token = response.next_page_token
        else:
            break
    
    return instances

def wait_for_operation(operation, project_id, zone):
    operation_client = compute_v1.ZoneOperationsClient()
    while True:
        result = operation_client.get(project=project_id, zone=zone, operation=operation.name)
        if result.status == compute_v1.Operation.Status.DONE:
            logger.info("Delete completed.")
            break
        elif result.error:
            raise Exception(f"Error during operation: {result.error}")
        else:
            logger.info("Waiting for delete operation to complete...")
            time.sleep(5)

def delete_instance(project_id, zone, instance_name, instance_client):
    operation = instance_client.delete(project=project_id, zone=zone, instance=instance_name)
    logger.info(f"Deleting instance {instance_name} in project {project_id}, zone {zone}...")
    wait_for_operation(operation, project_id, zone)

def delete_gcp_vm(project_id):
    instances = list_instances(project_id, zone)
    instance_client = compute_v1.InstancesClient()
    cutoff_date = datetime.now(timezone.utc) - timedelta(days=delete_interval)

    for instance in instances:
        if "do-not-delete-vm" in instance.labels and instance.labels["do-not-delete-vm"] == 'true':
            continue

        creation_timestamp = datetime.strptime(instance.creation_timestamp,"%Y-%m-%dT%H:%M:%S.%f%z")
        creation_timestamp = creation_timestamp.astimezone(pytz.UTC)            
        if creation_timestamp < cutoff_date:
            delete_instance(project_id, zone, instance.name, instance_client)

    return {"statusCode": 200, "message": "Images deleted successfully"}

def main(request=None):
    """HTTP Cloud Function to delete VM."""
    try:
        logger.info("Starting the main function...")
        response = delete_gcp_vm(project_id)
        logger.info(f"Function executed successfully. Response: {response}")
        return ( json.dumps(response), response.get("statusCode", 500), {"Content-Type": "application/json"}, )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        logger.error("".join(traceback.format_exc()))  # Log full traceback
        return ( json.dumps({"error": "Internal Server Error"}), 500, {"Content-Type": "application/json"},)

if __name__ == '__main__':
    main()
