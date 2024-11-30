import json
from google.cloud import compute_v1
from google.cloud import storage

def fetch_instance_data(project_id):
    instance_client = compute_v1.InstancesClient()
    disk_client = compute_v1.DisksClient()
    image_client = compute_v1.ImagesClient()
    results = []
    
    # List all instances in the project
    request = compute_v1.AggregatedListInstancesRequest(project=project_id)
    zones = instance_client.aggregated_list(request=request)

    for zone, instances_scoped_list in zones:
        if instances_scoped_list.instances:
            for instance in instances_scoped_list.instances:
                instance_name = instance.name
                vm_creation_time = instance.creation_timestamp
                zone_name = zone.split("/")[-1] if "/" in zone else zone
                creator = instance.labels.get("creator", "Unknown") if instance.labels else "Unknown"
                
                # Identify OS type
                os_type = "Unknown"
                if instance.metadata and instance.metadata.items:
                    os_type_item = next((item for item in instance.metadata.items if item.key == "os"), None)
                    os_type = os_type_item.value if os_type_item else "Unknown"

                # Iterate through attached disks
                for disk in instance.disks:
                    disk_source = disk.source
                    
                    if not disk_source:
                        continue
                    
                    # Extract disk name and zone
                    disk_name = disk_source.split("/")[-1]
                    disk_zone = disk_source.split("/zones/")[1].split("/")[0]
                    
                    # Fetch the source image URL from the disk
                    try:
                        disk_info = disk_client.get(project=project_id, zone=disk_zone, disk=disk_name)
                        source_image_url = disk_info.source_image
                    except Exception as e:
                        print(f"Error fetching disk info for {disk_name}: {e}")
                        continue
                    
                    if source_image_url:
                        # Extract image name and project from the source image URL
                        image_name = source_image_url.split("/")[-1]
                        image_project = source_image_url.split("/")[-4]
                        
                        # Fetch image labels and creation time
                        try:
                            image_info = image_client.get(project=image_project, image=image_name)
                            labels = dict(image_info.labels) if image_info.labels else {}
                            image_creation_time = image_info.creation_timestamp
                            deprecation_status = image_info.deprecated
                        except Exception as e:
                            print(f"Error fetching image info for {image_name}: {e}")
                            labels = {}
                            image_creation_time = "Unknown"
                            deprecation_status = None
                        
                        # Compliant status based on labels
                        compliant_val = "NON_COMPLIANT"
                        if labels and 'image_type' in labels:
                            if labels['image_type'] == 'golden-image':
                                compliant_val = "COMPLIANT"
                        
                        if deprecation_status: 
                            deprecation_status = deprecation_status.state
                                 
                        # Store the result
                        results.append({
                            "Project": project_id,
                            "VM Name": instance_name,
                            "Zone": zone_name,
                            "OS Type": os_type,
                            "VM Creator": creator,
                            "VM Creation Time": vm_creation_time,
                            "Source Image": image_name,
                            "Source Image Creation Time": image_creation_time,
                            "Labels": json.dumps(labels),
                            "Compliant Status": compliant_val,
                            "Deprecation Status": deprecation_status
                        })
                    else:
                        print(f"No source image found for disk {disk_name} in project {project_id}")
    
    return results

def save_to_excel(data, output_file):
    import pandas as pd
    df = pd.DataFrame(data)
    df.to_excel(output_file, index=False)
    print(f"Data saved to {output_file}")

def upload_to_gcs(file_path, bucket_name, destination_blob_name):
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        blob.upload_from_filename(file_path)
        print(f"File uploaded to gs://{bucket_name}/{destination_blob_name}")
    except Exception as e:
        print(f"Error uploading file to GCS: {e}")

def export_vm_image_labels():
    # List of project IDs
    projects = ["project-id-1", "project-id-2"]  # Replace with your actual project IDs
    bucket_name = "your-bucket-name"  # Replace with your GCS bucket name
    output_file = "vm_image_labels.xlsx"

    all_results = []

    # Process each project
    for project in projects:
        print(f"Processing Project: {project}")
        project_data = fetch_instance_data(project)
        all_results.extend(project_data)

    # Save results to Excel
    save_to_excel(all_results, output_file)
    
    # Upload the file to GCS
    upload_to_gcs(output_file, bucket_name, "vm_image_labels.xlsx")

if __name__ == "__main__":
    export_vm_image_labels()
