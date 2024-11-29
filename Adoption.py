import json
import pandas as pd
from google.cloud import compute_v1
from google.cloud import storage

def fetch_instance_data(project_id):
    # Initialize the Compute Engine clients
    instance_client = compute_v1.InstancesClient()
    disk_client = compute_v1.DisksClient()
    image_client = compute_v1.ImagesClient()
    
    results = []

    # List all zones in the project
    request = compute_v1.AggregatedListInstancesRequest(project=project_id)
    zones = instance_client.aggregated_list(request=request)

    # Iterate through all zones and instances
    for zone, instances_scoped_list in zones:
        if instances_scoped_list.instances:
            for instance in instances_scoped_list.instances:
                # Get VM name
                instance_name = instance.name
                
                # Iterate through attached disks
                for disk in instance.disks:
                    disk_source = disk.source
                    
                    if not disk_source:
                        continue
                    
                    # Extract disk name and zone
                    try:
                        disk_name = disk_source.split("/")[-1]
                        disk_zone = disk_source.split("/zones/")[1].split("/")[0]
                        
                        # Use DisksClient to fetch disk information
                        disk_info = disk_client.get(project=project_id, zone=disk_zone, disk=disk_name)
                        source_image_url = disk_info.source_image
                    except Exception as e:
                        print(f"Error fetching disk info for {disk_name}: {e}")
                        continue

                    if source_image_url:
                        # Extract the image name and project from the source image URL
                        try:
                            image_name = source_image_url.split("/")[-1]
                            image_project = source_image_url.split("/")[-3]
                            image_info = image_client.get(project=image_project, image=image_name)
                            labels = image_info.labels if image_info.labels else {}
                            deprecation_status = image_info.deprecated
                        except Exception as e:
                            print(f"Error fetching image info for {image_name}: {e}")
                            labels = {}
                            deprecation_status = None

                        # Append the result for this instance and its disk
                        results.append({
                            "Project": project_id,
                            "VM Name": instance_name,
                            "Source Image": image_name,
                            "Labels": json.dumps(labels),
                            "Deprecation Status": deprecation_status
                        })

    return results

def save_to_excel(data, output_file):
    # Convert the results to a DataFrame
    df = pd.DataFrame(data)
    
    # Save the DataFrame to an Excel file
    df.to_excel(output_file, index=False)
    print(f"Data saved to {output_file}")

def upload_to_gcs(file_path, bucket_name, destination_blob_name):
    # Upload the Excel file to a GCS bucket
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        blob.upload_from_filename(file_path)
        print(f"File uploaded to gs://{bucket_name}/{destination_blob_name}")
    except Exception as e:
        print(f"Error uploading file to GCS: {e}")

def export_vm_image_labels():
    # Define your project IDs and GCS bucket
    projects = ["project-id-1", "project-id-2"]  # Replace with your actual project IDs
    bucket_name = "your-bucket-name"  # Replace with your bucket name
    output_file = "vm_image_labels.xlsx"

    all_results = []

    # Process each project
    for project in projects:
        print(f"Processing Project: {project}")
        project_data = fetch_instance_data(project)
        all_results.extend(project_data)

    # Save the results to an Excel file
    save_to_excel(all_results, output_file)

    # Upload the Excel file to GCS
    upload_to_gcs(output_file, bucket_name, "vm_image_labels.xlsx")


if __name__ == "__main__":
    export_vm_image_labels()
