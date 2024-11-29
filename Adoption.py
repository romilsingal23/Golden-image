import subprocess
import json
from google.cloud import storage

def export_vm_image_labels():
    # Define your project IDs and GCS bucket
    projects = ["project-id-1", "project-id-2"]
    bucket_name = "your-bucket-name"
    output_file = "/tmp/vm_image_labels.json"

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

                    # Fetch the image labels
                    try:
                        labels_json = subprocess.check_output(
                            [
                                "gcloud", "compute", "images", "describe", image_name,
                                "--project", image_project,
                                "--format", "json(labels)"
                            ],
                            text=True
                        )
                        labels = json.loads(labels_json).get("labels", {})
                    except subprocess.CalledProcessError as e:
                        print(f"Error fetching labels for image {image_name}: {e}")
                        labels = {}

                    # Append the result
                    results.append({
                        "project": project,
                        "vm_name": instance_name,
                        "image_labels": labels
                    })

    # Save the results to a local JSON file
    with open(output_file, "w") as f:
        json.dump(results, f, indent=2)

    # Upload the JSON file to GCS
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob("vm_image_labels.json")
        blob.upload_from_filename(output_file)
        print(f"Export successful: File uploaded to gs://{bucket_name}/vm_image_labels.json")
    except Exception as e:
        print(f"Error uploading to GCS: {e}")

if __name__ == "__main__":
    export_vm_image_labels()
