import subprocess
import json
import pandas as pd
from google.cloud import storage

def export_vm_image_labels_to_excel():
    # Define your project IDs and GCS bucket
    projects = ["project-id-1", "project-id-2"]
    bucket_name = "your-bucket-name"
    output_file = "/tmp/vm_image_labels.xlsx"

    # Initialize the result list
    results = []

    for project in projects:
        print(f"Processing Project: {project}")

        # List instances in the project
        try:
            instances_json = subprocess.check_output(
                [
                    "gcloud", "compute", "instances", "list",
                    "--project", project,
                    "--format", "json"
                ],
                text=True
            )
            instances = json.loads(instances_json)
        except subprocess.CalledProcessError as e:
            print(f"Error fetching instances for project {project}: {e}")
            continue

        # Process each instance
        for instance in instances:
            instance_name = instance["name"]
            disks = instance.get("disks", [])

            for disk in disks:
                disk_source = disk.get("source", "")
                if not disk_source:
                    continue

                # Extract disk name and zone
                disk_name = disk_source.split("/")[-1]
                disk_zone = disk_source.split("/zones/")[1].split("/")[0]

                # Get the source image for the disk
                try:
                    source_image = subprocess.check_output(
                        [
                            "gcloud", "compute", "disks", "describe", disk_name,
                            "--zone", disk_zone,
                            "--project", project,
                            "--format", "value(sourceImage)"
                        ],
                        text=True
                    ).strip()
                except subprocess.CalledProcessError as e:
                    print(f"Error fetching source image for disk {disk_name}: {e}")
                    continue

                if source_image:
                    # Extract the image name and project
                    image_name = source_image.split("/")[-1]
                    image_project = source_image.split("/")[-3]

                    # Fetch the image details
                    try:
                        image_details_json = subprocess.check_output(
                            [
                                "gcloud", "compute", "images", "describe", image_name,
                                "--project", image_project,
                                "--format", "json"
                            ],
                            text=True
                        )
                        image_details = json.loads(image_details_json)
                        labels = image_details.get("labels", {})
                        deprecation_status = image_details.get("deprecated", {}).get("state", "N/A")
                    except subprocess.CalledProcessError as e:
                        print(f"Error fetching details for image {image_name}: {e}")
                        labels = {}
                        deprecation_status = "N/A"

                    # Append the result
                    results.append({
                        "Project": project,
                        "VM Name": instance_name,
                        "Source Image Name": image_name,
                        "Deprecation Status": deprecation_status,
                        "Image Labels": json.dumps(labels)  # Convert labels dict to string
                    })

    # Convert results to a DataFrame
    df = pd.DataFrame(results)

    # Save the DataFrame to an Excel file
    df.to_excel(output_file, index=False)
    print(f"Data exported to {output_file}")

    # Upload the Excel file to GCS
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob("vm_image_labels.xlsx")
        blob.upload_from_filename(output_file)
        print(f"Export successful: File uploaded to gs://{bucket_name}/vm_image_labels.xlsx")
    except Exception as e:
        print(f"Error uploading to GCS: {e}")

if __name__ == "__main__":
    export_vm_image_labels_to_excel()
