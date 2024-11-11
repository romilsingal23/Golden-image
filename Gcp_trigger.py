import os
import json
import logging
import traceback
from datetime import datetime, timezone
from google.cloud import storage
from google.cloud.devtools.cloudbuild_v1 import CloudBuildClient

# Initialize logging
logger = logging.getLogger()
logging.basicConfig(level=logging.INFO)

# Environment variables with default values
project_id = os.getenv('PROJECT_ID', "zjmqcnnb-gf42-i38m-a28a-y3gmil")  # Google Cloud Project ID
supported_images_bucket = os.getenv('SUPPORTED_IMAGES_BUCKET', "dev-supported-images")  # GCS bucket name for JSON file

# Initialize Google Cloud clients
storage_client = storage.Client()
cloud_build_client = CloudBuildClient()


def trigger_cloud_build(client, image_name, image):
    """Trigger a Cloud Build for a given image."""
    try:
        start_time = datetime.now(timezone.utc)

        # Define the build configuration
        build_config = {
            # 'source': {
            #     'storage_source': {
            #         'bucket': 'gcp-build1',
            #         'object': 'codebuild.zip'  # Path to the .zip file in the bucket
            #     }
            # },

            'steps': [
                {
                    'name': 'ubuntu',
                    'id': 'run-packer',
                    'entrypoint': 'bash',
                    'args': [
                        '-c',
                        'chmod +x execute_packer.sh && bash execute_packer.sh'
                    ],
                    'env': [
                        f'SOURCE_IMAGE_FAMILY={image.get("image_family")}',
                        f'IMAGE_NAME={image.get("image_name")}',
                        f'SSH_USERNAME={image.get("ssh_user", "default_user")}',
                        f'ARCHITECTURE={image.get("architecture", "x86")}',  # Defaulting to x86 if not specified
                        f'DATE_CREATED={datetime.strftime(start_time, "%Y-%m-%dT%H:%M:%S")}',
                        f'PROJECT_ID={project_id}'
                    ]
                }
            ],

            'substitutions': {
                'IMAGE_NAME': image.get('image_name'),
                'SOURCE_IMAGE_FAMILY': image.get('source_image_family'),
                'SSH_USERNAME': image.get('ssh_username', 'default_user'),  # Default username if not in JSON
                'DATE_CREATED': datetime.strftime(start_time, '%Y-%m-%dT%H:%M:%S'),
                #network_id = os.getenv('PROJECT_ID', "zjmqcnnb-gf42-i38m-a28a-y3gmil")

            }
        }
        logger.info("Start Test Build")
        logger.info(f"Start Test Build {image.get('source_image_family')}")
        
        

        # Trigger the build
        response = client.create_build(project_id= project_id, build= build_config)
        logger.info(f"Build triggered for {image_name} with build ID: {response} ")
        return response

    except Exception as e:
        logger.error(f"Failed to trigger build for {image_name}. Error: {str(e)}")
        logger.error("".join(traceback.format_exc()))  # Log full traceback
        raise


def handle():
    """Process the supported_images.json file and trigger builds."""
    try:
        # Read the supported_images.json file from GCS
        bucket = storage_client.bucket(supported_images_bucket)
        object = bucket.blob('supported_images.json')
        logger.info("Downloading supported_images.json...")
        file_content = object.download_as_text()

        # Parse the JSON content
        image_list_content = json.loads(file_content)
        image_list = image_list_content.get('gcp')

        if not image_list:
            logger.error("No GCP images found in the JSON file.")
            return {"statusCode": 400, "error": "No GCP images found in the provided JSON."}

        # Trigger Cloud Build for each image
        for name, image in image_list.items():
            logger.info(f"Triggering build for image: {name}")
            trigger_cloud_build(cloud_build_client, name, image)

        return {"statusCode": 200, "message": "Builds triggered successfully"}

    except Exception as e:
        logger.error(f"Error while processing request: {str(e)}")
        logger.error("".join(traceback.format_exc()))  # Log full traceback
        return {"statusCode": 500, "error": str(e)}


def main(request=None):
    """HTTP Cloud Function to handle requests."""
    try:
        logger.info("Starting the main function...")
        response = handle()
        logger.info(f"Function executed successfully. Response: {response}")
        return (
            json.dumps(response),
            response.get("statusCode", 500),
            {"Content-Type": "application/json"},
        )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        logger.error("".join(traceback.format_exc()))  # Log full traceback
        return (
            json.dumps({"error": "Internal Server Error"}),
            500,
            {"Content-Type": "application/json"},
        )

# Test block for local execution
if __name__ == "__main__":
    os.environ["PROJECT_ID"] = "zjmqcnnb-gf42-i38m-a28a-y3gmil"  # Replace with your actual Project ID
    os.environ["SUPPORTED_IMAGES_BUCKET"] = "dev-supported-images"  # Replace with your bucket name

    try:
        logger.info("Running main.py locally...")
        response = handle()
        logger.info(f"Response: {json.dumps(response, indent=4)}")
    except Exception as e:
        logger.error(f"An error occurred during local execution: {str(e)}")
        logger.error("".join(traceback.format_exc()))  # Log full traceback for local errors
