import os
import json
import pytz
import logging
from google.cloud import compute_v1
from datetime import datetime, timezone, timedelta

# Initialize logging
logger = logging.getLogger()
logging.basicConfig(level=logging.INFO)

delete_interval = 365
project_id = os.getenv('PROJECT_ID')  # Google Cloud Project ID
image_families = os.getenv('image_families').split(",")

logger.info(f"image_families {image_families}.")

def delete_gcp_image(project_id):
    client = compute_v1.ImagesClient()
    oldest = datetime.now(timezone.utc) - timedelta(days=delete_interval)
    deleted_status = compute_v1.DeprecationStatus(state="DELETED")
    for image_family in image_families:    
        filter_str = f"deprecated.state=OBSOLETE AND family={image_family}"
        request = compute_v1.ListImagesRequest(project=project_id, filter=filter_str)
        request.max_results = 300
        while True:
            images = client.list(request=request)
            for image in images:
                try:
                    creation_date = datetime.strptime(image.creation_timestamp,"%Y-%m-%dT%H:%M:%S.%f%z")
                    creation_date = creation_date.astimezone(pytz.UTC)
                    if creation_date < oldest:
                        operation = client.delete(project=project_id, image=image.name)
                        operation.result()
                        logger.info(f"Deleted image {image.name}.")
                except Exception as e:
                    logger.error(f"Failed to delete image {image.name}: {e}")
                    return {"statusCode": 500, "error": str(e)}

            if images.next_page_token:
                request.page_token = images.next_page_token
            else:
                break

    return {"statusCode": 200, "message": "Images deleted successfully"}

def main(request=None):
    """HTTP Cloud Function to delete images."""
    try:
        logger.info("Starting the main function...")
        response = delete_gcp_image(project_id)
        logger.info(f"Function executed successfully. Response: {response}")
        return ( json.dumps(response), response.get("statusCode", 500), {"Content-Type": "application/json"}, )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        logger.error("".join(traceback.format_exc()))  # Log full traceback
        return ( json.dumps({"error": "Internal Server Error"}), 500, {"Content-Type": "application/json"},)
