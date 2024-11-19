import os
import json
import boto3
from datetime import datetime, timezone, timedelta
from googleapiclient.discovery import build
from google.cloud import storage, pubsub_v1
from loguru import logger

# AWS Clients
dynamodb_client = boto3.client('dynamodb', region_name='us-east-1')

# GCP Clients
compute = build('compute', 'v1')
storage_client = storage.Client()
pubsub_publisher = pubsub_v1.PublisherClient()

# Environment Variables
pubsub_topic = os.getenv('PUBSUB_TOPIC', 'projects/your-project-id/topics/your-topic-name')
supported_images_bucket = os.getenv('SUPPORTED_IMAGES_BUCKET', 'your-bucket-name')
image_table = os.getenv('IMAGE_TABLE', 'image_table')  # DynamoDB table

VALID_OS_VERSIONS = {
    'debian-10', 'debian-11', 'ubuntu-20-04-lts', 'ubuntu-22-04-lts',
    'rhel-8', 'rhel-9', 'centos-7', 'centos-8', 'windows-2019', 'windows-2022'
}

# Deprecate Image in GCP
def deprecate_gcp_image(project_id, image_name):
    try:
        request = compute.images().deprecate(
            project=project_id,
            image=image_name,
            body={"state": "DEPRECATED"}
        )
        response = request.execute()
        logger.info(f"Deprecated image {image_name}: {response}")
        return True, None
    except Exception as e:
        logger.error(f"Failed to deprecate image {image_name}: {e}")
        return False, e

# Obsolete Image in GCP
def obsolete_gcp_image(project_id, image_name):
    try:
        request = compute.images().deprecate(
            project=project_id,
            image=image_name,
            body={"state": "OBSOLETE"}
        )
        response = request.execute()
        logger.info(f"Obsoleted image {image_name}: {response}")
        return True, None
    except Exception as e:
        logger.error(f"Failed to obsolete image {image_name}: {e}")
        return False, e

# Delete Image in GCP
def delete_gcp_image(project_id, image_name):
    try:
        request = compute.images().delete(project=project_id, image=image_name)
        response = request.execute()
        logger.info(f"Deleted image {image_name}: {response}")
        return True, None
    except Exception as e:
        logger.error(f"Failed to delete image {image_name}: {e}")
        return False, e

# Lifecycle Handler
def handle_lifecycle(project_id):
    now = datetime.now(timezone.utc)

    # Find Images from DynamoDB
    def find_images(status, days_offset):
        cutoff_date = now - timedelta(days=days_offset)
        expired_images = []
        params = {
            'TableName': image_table,
            'FilterExpression': 'status = :status AND date_created <= :cutoff',
            'ExpressionAttributeValues': {
                ':status': {'S': status},
                ':cutoff': {'S': cutoff_date.strftime('%Y-%m-%d %H:%M:%S')}
            }
        }
        response = dynamodb_client.scan(**params)
        for item in response.get('Items', []):
            expired_images.append(item['image_name']['S'])
        return expired_images

    # Deprecate images created yesterday
    images_to_deprecate = find_images('ACTIVE', days_offset=1)
    for image in images_to_deprecate:
        deprecate_gcp_image(project_id, image)

    # Obsolete images deprecated 30 days ago
    images_to_obsolete = find_images('DEPRECATED', days_offset=30)
    for image in images_to_obsolete:
        obsolete_gcp_image(project_id, image)

    # Delete images deprecated 1 year ago
    images_to_delete = find_images('DEPRECATED', days_offset=365)
    for image in images_to_delete:
        delete_gcp_image(project_id, image)

    return {"statusCode": 200, "message": "Lifecycle policy executed successfully"}

# Main Function
def main(event):
    project_id = event.get('project_id', 'your-project-id')
    return handle_lifecycle(project_id)
