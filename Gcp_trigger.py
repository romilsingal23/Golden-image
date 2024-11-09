import os
import json
import logging
from datetime import datetime, timezone
from google.cloud import build_v1
from google.cloud import storage
from google.cloud.devtools import cloudbuild_v1
from google.cloud.devtools.cloudbuild_v1 import CloudBuildClient

# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
project_id = os.getenv('PROJECT_ID')  # Google Cloud Project ID
supported_images_bucket = os.getenv('SUPPORTED_IMAGES_BUCKET')  # GCS bucket name for JSON file

# Google Cloud Storage client
storage_client = storage.Client()

# Cloud Build client to trigger builds
cloud_build_client = CloudBuildClient()


def trigger_cloud_build(client, image_name, image):
    """Trigger a Cloud Build for a given image."""
    try:
        start_time = datetime.now(timezone.utc)

        # Define the build configuration
        build_config = {
            'source': {
                'storage_source': {
                    'bucket': 'gcp-build1',
                    'object': 'cloudbuild.zip'  # Path to the .zip file in the bucket
                }
            },
            'substitutions': {
                '_IMAGE_NAME': image['image_name'],
                '_IMAGE_FAMILY': image['image_family'],
                '_SOURCE_IMAGE': image.get('source_image'),
                '_SSH_USERNAME': image.get('ssh_username'),
                '_DISK_SIZE': image.get('disk_size'),
                '_DATE_CREATED': datetime.strftime(start_time)
            }
        }

        # Trigger the build
        response = client.create_build(project_id=project_id, build=build_config)
        logger.info(f"Build triggered for {image_name} with build ID: {response.name}")
        return response

    except Exception as e:
        logger.error(f"Failed to trigger build for {image_name}. Error: {str(e)}")
        raise


def handle():
    """Process the supported_images.json file and trigger builds."""
    try:
        # Read the supported_images.json file from GCS
        bucket = storage_client.bucket(dev-supported-images)
        blob = bucket.blob('supported_images.json')
        file_content = blob.download_as_text()

        # Parse the JSON content
        image_list_content = json.loads(file_content)
        image_list = image_list_content.get('gcp')

        if not image_list:
            logger.error("No GCP images found in the JSON file.")
            return {"statusCode": 400, "error": "No GCP images found in the provided JSON."}

        # Trigger Cloud Build for each image
        for name, image in image_list.items():
            trigger_cloud_build(cloud_build_client, name, image)

        return {"statusCode": 200, "message": "Builds triggered successfully"}

    except Exception as e:
        logger.error(f"Error while processing request: {str(e)}")
        return {"statusCode": 500, "error": str(e)}


def main(request):
    """HTTP Cloud Function to handle requests."""
    try:
        # Call the handle function
        response = handle()

        # Return an HTTP response
        return (
            json.dumps(response),
            response.get("statusCode", 500),
            {"Content-Type": "application/json"},
        )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return (
            json.dumps({"error": "Internal Server Error"}),
            500,
            {"Content-Type": "application/json"},
        )
