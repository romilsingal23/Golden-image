from google.cloud import compute_v1, storage
import datetime
import subprocess
from dateutil import parser  # Importing dateutil for parsing timestamps

def move_images_to_storage():
    project_id = "your-project-id"  # Replace with your GCP project ID
    bucket_name = "your-bucket-name"  # Replace with your Cloud Storage bucket name
    storage_class = "COLDLINE"  # Options: STANDARD, NEARLINE, COLDLINE, ARCHIVE
    client = compute_v1.ImagesClient()
    storage_client = storage.Client()

    # Calculate the threshold date (5 days ago for testing)
    threshold_days = 5
    today = datetime.datetime.now(datetime.timezone.utc)
    threshold_date = today - datetime.timedelta(days=threshold_days)

    print(f"Threshold date: {threshold_date}")

    # List all custom images in the project
    print("Fetching images...")
    images = client.list(project=project_id)
    for image in images:
        # Parse the creation timestamp using dateutil.parser
        creation_time = parser.parse(image.creation_timestamp)

        # Check if the image is older than 5 days
        if creation_time < threshold_date:
            print(f"Processing image: {image.name} (Created on: {creation_time})")
            
            # Define the destination URI in Cloud Storage
            destination_uri = f"gs://{bucket_name}/{image.name}.tar.gz"

            try:
                # Export the image to Cloud Storage using gcloud CLI
                print(f"Exporting image {image.name} to {destination_uri}...")
                subprocess.run([
                    "gcloud", "compute", "images", "export",
                    f"--destination-uri={destination_uri}",
                    f"--image={image.name}",
                    f"--project={project_id}"
                ], check=True)

                print(f"Export successful for image: {image.name}")

                # Set the storage class of the uploaded file (optional)
                print(f"Updating storage class of {image.name}.tar.gz to {storage_class}...")
                bucket = storage_client.bucket(bucket_name)
                blob = bucket.blob(f"{image.name}.tar.gz")
                blob.update_storage_class(storage_class)

                # Delete the image from Compute Engine after export
                print(f"Deleting image: {image.name}")
                client.delete(project=project_id, image=image.name)
            except Exception as e:
                print(f"Error processing image {image.name}: {e}")

    print("All old images have been processed.")

# Run the function
if __name__ == "__main__":
    move_images_to_storage()
