from google.cloud import compute_v1
from datetime import datetime, timedelta, timezone

# Configuration
PROJECT_ID = "prj-ospacker-useast-dev-23295"  # Extracted from error message
DEPRECATION_STATE = "OBSOLETE"
EXPIRY_DAYS = 120  # 4 months = 120 days

def get_old_images():
    """Fetches images older than 4 months."""
    image_client = compute_v1.ImagesClient()
    images = image_client.list(project=PROJECT_ID)

    threshold_date = datetime.now(timezone.utc) - timedelta(days=EXPIRY_DAYS)
    old_images = []

    for image in images:
        if image.creation_timestamp:
            creation_time = datetime.strptime(image.creation_timestamp, "%Y-%m-%dT%H:%M:%S.%f%z")
            if creation_time < threshold_date:
                old_images.append(image)

    return old_images

def obsolete_image(image_name):
    """Marks the image as OBSOLETE with correct RFC 3339 timestamp format."""
    image_client = compute_v1.ImagesClient()

    # Convert datetime to RFC 3339 format (YYYY-MM-DDTHH:MM:SS.sssZ)
    obsolete_time = datetime.now(timezone.utc).isoformat(timespec="milliseconds")

    deprecation_status = compute_v1.DeprecationStatus(
        state=DEPRECATION_STATE,
        obsolete=obsolete_time
    )

    operation = image_client.deprecate(
        project=PROJECT_ID, image=image_name, deprecation_status_resource=deprecation_status
    )

    return operation

if __name__ == "__main__":
    old_images = get_old_images()
    
    if not old_images:
        print("No images older than 4 months found.")
    else:
        for img in old_images:
            print(f"Obsoleting image: {img.name} in project {PROJECT_ID}")
            operation = obsolete_image(img.name)
            print(f"Obsolete request sent for {img.name}, operation ID: {operation.name}")
