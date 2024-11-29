import json
import subprocess
from google.cloud import storage

def fetch_instance_data_using_gcloud(project_id):
    try:
        # Use gcloud CLI to fetch instance details
        result = subprocess.check_output(
            [
                "gcloud",
                "compute",
                "instances",
                "list",
                f"--project={project_id}",
                "--format=json"
            ]
        )
        instances = json.loads(result)
        return instances
    except Exception as e:
        print(f"Error fetching instance data for project {project_id}: {e}")
        return []

def fetch_disk_and_image_details(project_id, instance):
    instance_name = instance.get("name")
    zone = instance.get("zone").split("/")[-1]
    disks = instance.get("disks", [])

    results = []

    for disk in disks:
        disk_url = disk.get("source")
        if not disk_url:
            print(f"No disks found for instance: {instance_name} in zone: {zone}")
            continue

        # Extract disk name and zone
        disk_name = disk_url.split("/")[-1]
        disk_zone = disk_url.split("/zones/")[1].split("/")[0]

        try:
            # Use gcloud CLI to describe the disk and fetch its source image
            image_url = subprocess.check_output(
                [
                    "gcloud",
                    "compute",
                    "disks",
                    "describe",
                    disk_name,
                    f"--zone={disk_zone}",
                    f"--project={project_id}",
                    "--format=value(sourceImage)"
                ]
            ).decode("utf-8").strip()

            if image_url:
                # Extract the image name and project from the image URL
                image_name = image_url.split("/")[-1]
                image_project = image_url.split("/")[-3]

                # Fetch labels of the image
                labels = subprocess.check_output(
                    [
                        "gcloud",
                        "compute",
                        "images",
                        "describe",
                        image_name,
                        f"--project={image_project}",
                        "--format=json(labels)"
                    ]
                ).decode("utf-8")

                results.append({
                    "VM Name": instance_name,
                    "Disk": disk_name,
                    "Image Name": image_name,
                    "Labels": labels
                })
            else:
                print(f"No source image found for instance: {instance_name}")
        except Exception as e:
            print(f"Error processing disk {disk_name}: {e}")
            continue

    return results

def process_projects_and_save_to_file(projects, output_file):
    all_results = []

    for project_id in projects:
        print(f"Processing Project: {project_id}")
        instances = fetch_instance_data_using_gcloud(project_id)

        for instance in instances:
            instance_results = fetch_disk_and_image_details(project_id, instance)
            all_results.extend(instance_results)

    # Save the results to a JSON file
    with open(output_file, "w") as f:
        json.dump(all_results, f, indent=4)

    print(f"Results saved to {output_file}")

def upload_to_gcs(file_path, bucket_name, destination_blob_name):
    # Upload the file to Google Cloud Storage
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        blob.upload_from_filename(file_path)
        print(f"File uploaded to gs://{bucket_name}/{destination_blob_name}")
    except Exception as e:
        print(f"Error uploading file to GCS: {e}")

def main():
    # Define your project IDs and GCS bucket
    projects = ["project-id-1", "project-id-2"]  # Replace with actual project IDs
    bucket_name = "your-bucket-name"  # Replace with your GCS bucket name
    output_file = "vm_image_labels.json"  # Local output file name

    # Step 1: Process projects and save results locally
    process_projects_and_save_to_file(projects, output_file)

    # Step 2: Upload the results to Google Cloud Storage
    upload_to_gcs(output_file, bucket_name, "vm_image_labels.json")

if __name__ == "__main__":
    main()
