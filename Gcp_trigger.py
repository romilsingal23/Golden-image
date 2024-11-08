import os
import json
import logging
from datetime import datetime, timezone
from google.cloud import storage, cloudbuild_v1

# Initialize logging
logger = logging.getLogger()
logger.setLevel("INFO")

# Project and bucket settings
project_id = os.getenv('GCP_PROJECT_ID', 'your_project_id')
supported_images_bucket = os.getenv('supported_images_bucket', 'your_bucket_name')

# Initialize GCP clients
storage_client = storage.Client()
cloud_build_client = cloudbuild_v1.services.cloud_build.CloudBuildClient()

def trigger_cloud_build(client, image_name, image):
    start_time = datetime.now(timezone.utc)

    # Define the build configuration with substitutions
    build_config = {
        'source': {
            'storage_source': {
                'bucket': supported_images_bucket,
                'object': 'path/to/your/codebuild.yaml'
            }
        },
        'substitutions': {
            '_IMAGE_FAMILY': image['image_family'],
            '_OS_TYPE': image['os_type'],
            '_IMAGE_PROJECT': image['image_project'],
            '_IMAGE_NAME': image['image_name'],
            '_ARCHITECTURE': image['architecture'],
            '_DEVICE_TYPE': image['device_type'],
            '_ROOT_VOLUME': image['root_volume'],
            '_SSH_USER': image['ssh_user'],
            '_VIRTUALIZATION_TYPE': image['virtualization_type'],
            '_DATE_CREATED': datetime.strftime(start_time, '%Y-%m-%d-%H%M%S')
        }
    }

    # Start the Cloud Build
    response = client.create_build(project_id=project_id, build=build_config)
    logger.info(f"Build triggered for {image_name} with build ID: {response.name}")
    return response

def handle(client):
    try:
        # Reading the JSON file from Google Cloud Storage
        bucket = storage_client.get_bucket(supported_images_bucket)
        blob = bucket.blob('supported_images.json')
        file_content = blob.download_as_text()
    except Exception as e:
        logger.error(f"Error while reading GCS object: {str(e)}")
        return {"statusCode": 500, "error": "Error while reading GCS object."}

    # Load and parse JSON content
    image_list_content = json.loads(file_content)
    image_list = image_list_content.get('gcp', {})

    # Trigger build for each image in the GCP list
    for name, image in image_list.items():
        trigger_cloud_build(client, name, image)

    return {"statusCode": 200}

# Main entry point for GCP (e.g., Cloud Function)
def gcp_function_entry_point(event, context):
    return handle(cloud_build_client)
