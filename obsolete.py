import os
import json
import pytz
import boto3
import logging
import traceback
from google.cloud import compute_v1
from google.cloud import secretmanager
from datetime import datetime, timezone, timedelta

# Initialize logging
logger = logging.getLogger()
logging.basicConfig(level=logging.INFO)

obsoleted_interval = 30
aws_access_key = os.getenv('aws_access_key')
aws_secret_key = os.getenv('aws_secret_key')
project_id = os.getenv('PROJECT_ID')  # Google Cloud Project ID
image_families = os.getenv('image_families').split(",")
image_table =  os.getenv('dynamodb_table')

logger.info(f"Image Families List {image_families}.")

def get_secret_gcp(secret_id):
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

def update_dynamodb_inactive(db_client, image_name):
    try:
        key = { 'csp': {'S': 'gcp'}, 'image_name': {'S': image_name} }
        db_client.update_item(TableName=image_table, Key=key, 
            UpdateExpression='SET active = :disable',
            ExpressionAttributeValues={ ':disable': {'S': 'false'} } )
        logger.info({'action': 'deactivate', 'item': key})
        return True
    except Exception as e:
        logger.error(f"Unexpected error in update_dynamodb_inactive: {str(e)}")
        return False

def obsolete_gcp_image(project_id):
    client = compute_v1.ImagesClient()
    oldest = datetime.now(timezone.utc) - timedelta(days=obsoleted_interval)
    obsoleted_status = compute_v1.DeprecationStatus(state="OBSOLETE")
    access_key = get_secret_gcp(aws_access_key)
    secret_key = get_secret_gcp(aws_secret_key)
    db_client = boto3.client('dynamodb', region_name='us-east-1'
    , aws_access_key_id=access_key, aws_secret_access_key=secret_key)
    for image_family in image_families:
        filter_str = f"deprecated.state=DEPRECATED AND family={image_family}"
        request = compute_v1.ListImagesRequest(project=project_id, filter=filter_str)
        request.max_results = 300
        while True:
            images = client.list(request=request)
            for image in images:
                try:
                    creation_date = datetime.strptime(image.creation_timestamp,"%Y-%m-%dT%H:%M:%S.%f%z")
                    creation_date = creation_date.astimezone(pytz.UTC)
                    if creation_date < oldest:
                        client.deprecate(project=project_id, image=image.name
                        , deprecation_status_resource=obsoleted_status)
                        logger.info(f"Obsoleted image {image.name}.")
                        update_dynamodb_inactive(db_client, image.name)      
                except Exception as e:
                    logger.error(f"Failed to obsolete image {image.name}: {e}")
                    return {"statusCode": 500, "error": str(e)}

            if images.next_page_token:
                request.page_token = images.next_page_token
            else:
                break

    return {"statusCode": 200, "message": "Images obsoleted successfully"}

def main(request=None):
    """HTTP Cloud Function to Obsolete images."""
    try:
        logger.info("Starting the main function...")
        response = obsolete_gcp_image(project_id)
        logger.info(f"Function executed successfully. Response: {response}")
        return ( json.dumps(response), response.get("statusCode", 500), {"Content-Type": "application/json"}, )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        logger.error("".join(traceback.format_exc()))  # Log full traceback
        return ( json.dumps({"error": "Internal Server Error"}), 500, {"Content-Type": "application/json"},) 
