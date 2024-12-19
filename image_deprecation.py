import os
import json
import pytz
import logging
from google.cloud import compute_v1
from datetime import datetime, timezone, timedelta

# Initialize logging
logger = logging.getLogger()
logging.basicConfig(level=logging.INFO)

image_family = os.getenv('GIM_FAMILY')  # Google Cloud image family
project_id = os.getenv('PROJECT_ID')  # Google Cloud Project ID

def deprecate_gcp_image(project_id, image_name):
    client = compute_v1.ImagesClient()
    filter_str = f"family={image_family} AND status=READY AND name!={image_name}"
    request = compute_v1.ListImagesRequest(project=project_id, filter=filter_str)
    images = client.list(request=request)
    deprecation_status = compute_v1.DeprecationStatus(state="DEPRECATED")
    for image in images:
        try:
            if str(image.deprecated.state) == "":
                client.deprecate(project=project_id, image=image.name
                , deprecation_status_resource=deprecation_status)
                logger.info(f"Deprecated image {image.name}.")
        except Exception as e:
            logger.error(f"Failed to deprecate image {image.name}: {e}")
            return False, e
    return True, "Successfully Deprecated Images"
