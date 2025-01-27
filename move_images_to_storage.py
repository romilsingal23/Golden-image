from google.cloud import compute_v1, storage
import datetime
import subprocess

def move_images_to_storage():
    project_id = "your-project-id"  # Replace with your GCP project ID
    bucket_name = "your-bucket-name"  # Replace with your Cloud Storage bucket name
    storage_class = "COLDLINE"  # Options: STANDARD, NEARLINE, COLDLINE, ARCHIVE
    client = compute_v1.ImagesClient()
    storage_client = storage.Client()

    # Calculate the threshold date (5 days ago for testing)
    threshold_days = 5
    today = datetime.datetime.now(datetime.timezone.utc)
    threshold_date = today - datetime.timedelta(days=threshold_days)  # Use 5 days for testing

    # List all custom images in the project
    print("Fetching images...")
    images = client.list(project=project_id)
    for image in images:
        creation_time = datetime.datetime.fromisoformat(image.creation_timestamp[:-1])  # Parse creation time
        
        # Check if the image is older than 5 days
        if creation_time < threshold_date:
            print(f"Processing image: {image.name} (Created on: {creation_time})")
            
            # Define the destination URI in Cloud Storage
            destination_uri = f"gs://{bucket_name}/{image.name}.tar.gz"

            # Export the image to Cloud Storage using gcloud CLI
            print(f"Exporting image {image.name} to {destination_uri}...")
            subprocess.run([
                "gcloud", "compute", "images", "export",
                f"--destination-uri={destination_uri}",
                f"--image={image.name}",
                f"--project={project_id}"
            ], check=True)

            # Set the storage class of the uploaded file (optional)
            print(f"Updating storage class of {image.name}.tar.gz to {storage_class}...")
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(f"{image.name}.tar.gz")
            blob.update_storage_class(storage_class)

            # Delete the image from Compute Engine after export
            print(f"Deleting image: {image.name}")
            client.delete(project=project_id, image=image.name)

    print("All old images have been processed.")
