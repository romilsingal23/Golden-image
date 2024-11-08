import os
import json
import logging
from datetime import datetime, timezone
from google.cloud import build_v1
from google.cloud import storage

# Initialize logging
logger = logging.getLogger()
logger.setLevel("INFO")

# Environment variables
project_id = os.getenv('PROJECT_ID', 'your-project-id')  # Google Cloud Project ID
supported_images_bucket = os.getenv('SUPPORTED_IMAGES_BUCKET', 'your-bucket-name')  # S3 bucket name

# Google Cloud Storage client (used to read the JSON file from the bucket)
storage_client = storage.Client()

# Cloud Build client to trigger builds
cloud_build_client = build_v1.CloudBuildClient()

def trigger_cloud_build(client, image_name, image):
    start_time = datetime.now(timezone.utc)

    # Define the build configuration for triggering the Packer build
    build_config = {
        'substitutions': {
            '_IMAGE_NAME': image['image_name'],  # Image name to create
            '_IMAGE_FAMILY': image['image_family'],  # Image family
            '_PROJECT_ID': project_id,  # Project ID where image will be created
            '_ZONE': image.get('zone', 'us-central1-a'),  # Zone for the instance (default to 'us-central1-a')
            '_SOURCE_IMAGE': image.get('source_image', 'debian-10-buster-v20210817'),  # Source image to use (default to a Debian image)
            '_SSH_USERNAME': image.get('ssh_user', 'cloud-user'),  # SSH username, default 'cloud-user' if not provided
            '_MACHINE_TYPE': image.get('machine_type', 'n1-standard-1'),  # Machine type (default to 'n1-standard-1')
            '_DISK_SIZE': image.get('disk_size', 10),  # Disk size (default to 10 GB)
            '_NETWORK': image.get('network', 'default'),  # Network configuration (default to 'default')
            '_DATE_CREATED': datetime.strftime(start_time, '%Y-%m-%d-%H%M%S')  # Timestamp of when the build is triggered
        }
    }

    # Start the Cloud Build job
    response = client.create_build(project_id=project_id, build=build_config)
    logger.info(f"Build triggered for {image_name} with build ID: {response.name}")
    return response


def handle():
    try:
        # Reading the supported_images.json file from Google Cloud Storage
        bucket = storage_client.bucket(supported_images_bucket)
        blob = bucket.blob('supported_images.json')  # Assuming the file is named 'supported_images.json'
        file_content = blob.download_as_text()

    except Exception as e:
        logger.error(f"Error while reading GCS object. Error - {str(e)}")
        return {"statusCode": 500, "error": "Error while reading GCS object."}
    
    # Parse the JSON content
    try:
        image_list_content = json.loads(file_content)
        image_list = image_list_content.get('gcp', {})
        
        if not image_list:
            raise ValueError("No GCP images found in the provided JSON.")
        
        for name, image in image_list.items():
            trigger_cloud_build(cloud_build_client, name, image)

        return {"statusCode": 200, "message": "Builds triggered successfully"}

    except Exception as e:
        logger.error(f"Error while processing the JSON file. Error - {str(e)}")
        return {"statusCode": 500, "error": "Error while processing JSON file."}


def main(request):
    """HTTP Cloud Function to trigger Cloud Build based on the supported_images.json."""
    return handle()
