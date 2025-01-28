from google.cloud import compute_v1
from datetime import datetime, timedelta, timezone

# Configuration
PROJECT_ID = "prj-ospacker-useast-dev-23295"
DEPRECATION_STATE = "DEPRECATED"
OBSOLETE_STATE = "OBSOLETE"
EXPIRY_DAYS_DEPRECATE = 60  # 2 months = 60 days
EXPIRY_DAYS_OBSOLETE = 120  # 4 months = 120 days
DELETE_YEARS = 7  # 7 years before deletion

def get_images_to_deprecate_or_obsolete():
    """Fetches images for deprecation and obsolescence."""
    image_client = compute_v1.ImagesClient()
    images = image_client.list(project=PROJECT_ID)

    # Define threshold dates for deprecation (2 months) and obsolescence (4 months)
    deprecate_threshold = datetime.now(timezone.utc) - timedelta(days=EXPIRY_DAYS_DEPRECATE)
    obsolete_threshold = datetime.now(timezone.utc) - timedelta(days=EXPIRY_DAYS_OBSOLETE)

    images_to_deprecate = []
    images_to_obsolete = []

    for image in images:
        if image.creation_timestamp:
            creation_time = datetime.strptime(image.creation_timestamp, "%Y-%m-%dT%H:%M:%S.%f%z")
            if creation_time < deprecate_threshold and creation_time >= obsolete_threshold:
                images_to_deprecate.append(image)
            elif creation_time < obsolete_threshold:
                images_to_obsolete.append(image)

    return images_to_deprecate, images_to_obsolete

def deprecate_image(image_name):
    """Marks the image as DEPRECATED with the correct RFC 3339 timestamp format."""
    image_client = compute_v1.ImagesClient()

    # Convert datetime to RFC 3339 format (YYYY-MM-DDTHH:MM:SS.sssZ)
    deprecate_time = datetime.now(timezone.utc).isoformat(timespec="milliseconds")

    deprecation_status = compute_v1.DeprecationStatus(
        state=DEPRECATION_STATE,
        deprecated=deprecate_time
    )

    operation = image_client.deprecate(
        project=PROJECT_ID, image=image_name, deprecation_status_resource=deprecation_status
    )

    return operation

def obsolete_image(image_name):
    """Marks the image as OBSOLETE with the correct RFC 3339 timestamp format."""
    image_client = compute_v1.ImagesClient()

    # Convert datetime to RFC 3339 format (YYYY-MM-DDTHH:MM:SS.sssZ)
    obsolete_time = datetime.now(timezone.utc).isoformat(timespec="milliseconds")

    deprecation_status = compute_v1.DeprecationStatus(
        state=OBSOLETE_STATE,
        obsolete=obsolete_time
    )

    operation = image_client.deprecate(
        project=PROJECT_ID, image=image_name, deprecation_status_resource=deprecation_status
    )

    return operation

def delete_image(image_name):
    """Deletes the image after 7 years."""
    image_client = compute_v1.ImagesClient()

    operation = image_client.delete(
        project=PROJECT_ID, image=image_name
    )

    return operation

def get_old_images_for_deletion():
    """Fetches images older than 7 years."""
    image_client = compute_v1.ImagesClient()
    images = image_client.list(project=PROJECT_ID)

    threshold_date = datetime.now(timezone.utc) - timedelta(days=DELETE_YEARS * 365)  # 7 years
    images_to_delete = []

    for image in images:
        if image.creation_timestamp:
            creation_time = datetime.strptime(image.creation_timestamp, "%Y-%m-%dT%H:%M:%S.%f%z")
            if creation_time < threshold_date:
                images_to_delete.append(image)

    return images_to_delete

if __name__ == "__main__":
    # Fetch images to deprecate and obsolete
    images_to_deprecate, images_to_obsolete = get_images_to_deprecate_or_obsolete()

    if not images_to_deprecate and not images_to_obsolete:
        print("No images to deprecate or obsolete found.")
    else:
        for img in images_to_deprecate:
            print(f"Deprecating image: {img.name} in project {PROJECT_ID}")
            operation = deprecate_image(img.name)
            print(f"Deprecate request sent for {img.name}, operation ID: {operation.name}")

        for img in images_to_obsolete:
            print(f"Obsoleting image: {img.name} in project {PROJECT_ID}")
            operation = obsolete_image(img.name)
            print(f"Obsolete request sent for {img.name}, operation ID: {operation.name}")

    # Check for images older than 7 years and delete them
    images_to_delete = get_old_images_for_deletion()

    if not images_to_delete:
        print("No images older than 7 years found for deletion.")
    else:
        for img in images_to_delete:
            print(f"Deleting image: {img.name} in project {PROJECT_ID}")
            operation = delete_image(img.name)
            print(f"Delete request sent for {img.name}, operation ID: {operation.name}")
