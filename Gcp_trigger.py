import os
import json
import logging
from datetime import datetime, timezone
from google.cloud import storage
from googleapiclient import discovery

# Project name and bucket variables
project_name = os.getenv('PROJECT_NAME', 'project_name')
supported_images_bucket = os.getenv('SUPPORTED_IMAGES_BUCKET', 'error')

# Configure logging
logger = logging.getLogger()
logger.setLevel("INFO")

# Google Cloud clients (no explicit credentials needed in Cloud Functions)
cloudbuild_client = discovery.build('cloudbuild', 'v1')
storage_client = storage.Client()

def trigger_build(client, image_name, image):
    start_time = datetime.now(timezone.utc)
    build_request = {
        'projectId': project_name,
        'source': {
            'storageSource': {
                'bucket': supported_images_bucket,
                'object': 'supported_images.json'
            }
        },
        'substitutions': {
            '_IMAGE_FAMILY': image_name,
            '_OS_TYPE': image['os_type'],
            '_OS_OWNER': image['owner'],
            '_OS_NAME': image['name_filter'],
            '_OS_ARCH': image['architecture'],
            '_OS_VIRTUALIZATION': image['virtualization_type'],
            '_OS_MAPPING': image['device_mapping'],
            '_OS_DEVICE': image['device_type'],
            '_OS_ROOT_VOLUME': image['root_volume'],
            '_SSH_USER': image['ssh_user'],
            '_DATE_CREATED': datetime.strftime(start_time, '%Y-%m-%d-%H%M%S')
        }
    }

    try:
        client.projects().builds().create(projectId=project_name, body=build_request).execute()
        logger.info(f"Triggered build for image: {image_name}")
    except Exception as e:
        logger.error(f"Error triggering build for image {image_name}: {e}")

def handle():
    try:
        # Reading the Cloud Storage object - supported images JSON file
        bucket = storage_client.bucket(supported_images_bucket)
        blob = bucket.blob('supported_images.json')
        file_content = blob.download_as_text()
    except Exception as e:
        logger.error('Error while reading Cloud Storage object. Error - ' + str(e))
        return {"statusCode": 500, "error": "Error while reading Cloud Storage object."}

    image_list_content = json.loads(file_content)
    image_list = image_list_content.get('gcp', {})

    for name, image in image_list.items():
        trigger_build(cloudbuild_client, name, image)
    return {"statusCode": 200}

def main(request):
    return handle()
