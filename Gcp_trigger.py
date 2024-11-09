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
supported_images_bucket = os.getenv('SUPPORTED_IMAGES_BUCKET', 'your-bucket-name')  # GCS bucket name for JSON file

# Google Cloud Storage client
storage_client = storage.Client()

# Cloud Build client to trigger builds
cloud_build_client = build_v1.CloudBuildClient()

def trigger_cloud_build(client, image_name, image):
    start_time = datetime.now(timezone.utc)

    # Define the build configuration to point to a zipped source containing cloudbuild.yaml
    build_config = {
        'source': {
            'storage_source': {
                'bucket': supported_images_bucket,  # Bucket containing the .zip file
                'object': 'path/to/cloudbuild.zip'  # Path to the .zip file in the bucket
            }
        },
        'substitutions': {
            '_IMAGE_NAME': image['image_name'],
            '_IMAGE_FAMILY': image['image_family'],
            '_PROJECT_ID': project_id,
            '_ZONE': image.get('zone', 'us-central1-a'),
            '_SOURCE_IMAGE': image.get('source_image', 'debian-10-buster-v20210817'),
            '_SSH_USERNAME': image.get('ssh_user', 'cloud-user'),
            '_MACHINE_TYPE': image.get('machine_type', 'n1-standard-1'),
            '_DISK_SIZE': image.get('disk_size', 10),
            '_NETWORK': image.get('network', 'default'),
            '_DATE_CREATED': datetime.strftime(start_time, '%Y-%m-%d-%H%M%S')
        }
    }

    # Start the Cloud Build job
    response = client.create_build(project_id=project_id, build=build_config)
    logger.info(f"Build triggered for {image_name} with build ID: {response.name}")
    return response

def handle():
    try:
        # Read the supported_images.json file from Google Cloud Storage
        bucket = storage_client.bucket(supported_images_bucket)
        blob = bucket.blob('supported_images.json')  # Assuming the JSON file is named 'supported_images.json'
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
