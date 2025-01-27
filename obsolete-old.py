from google.cloud import compute_v1
from datetime import datetime, timedelta

# Configuration
PROJECT_ID = "your-project-id"  # Replace with your GCP project ID
DEPRECATION_STATE = "OBSOLETE"  # State to set the image to
EXPIRY_DAYS = 120  # 4 months = 120 days

def get_old_images():
    """Fetches images older than 4 months."""
    image_client = compute_v1.ImagesClient()
    images = image_client.list(project=PROJECT_ID)

    threshold_date = datetime.utcnow() - timedelta(days=EXPIRY_DAYS)
    old_images = []

    for image in images:
        if image.creation_timestamp:
            creation_time = datetime.strptime(image.creation_timestamp, "%Y-%m-%dT%H:%M:%S.%f%z")
            if creation_time < threshold_date:
                old_images.append(image)

    return old_images

def obsolete_image(image_name):
    """Marks the image as OBSOLETE."""
    image_client = compute_v1.ImagesClient()

    deprecation_status = compute_v1.DeprecationStatus(
        state=DEPRECATION_STATE,
        obsolete=datetime.utcnow().isoformat() + "Z"
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
            print(f"Obsoleting image: {img.name}")
            operation = obsolete_image(img.name)
            print(f"Obsolete request sent for {img.name}, operation ID: {operation.name}")
