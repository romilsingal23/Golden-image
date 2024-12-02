import json
from google.cloud import compute_v1
from google.cloud import storage
from google.cloud import iam_v1
import pandas as pd

def fetch_project_owner(project_id):
    # Initialize IAM client
    iam_client = iam_v1.IAMPolicyClient()
    results = []

    # Retrieve the IAM policy for the project
    resource = f"projects/{project_id}"
    policy = iam_client.get_iam_policy(resource=resource)

    # Collect emails for users with the 'roles/owner' role
    owners = []
    for binding in policy.bindings:
        if binding.role == "roles/owner":
            for member in binding.members:
                # Extract the email address from the member
                if member.startswith("user:"):
                    owners.append(member.split(":")[1])

    return ", ".join(owners) if owners else "No owners found"

def fetch_instance_data(project_id):
    instance_client = compute_v1.InstancesClient()
    disk_client = compute_v1.DisksClient()
    image_client = compute_v1.ImagesClient()
    results = []

    # Get the project owner
    project_owner = fetch_project_owner(project_id)

    # List all instances in the project
    request = compute_v1.AggregatedListInstancesRequest(project=project_id)
    zones = instance_client.aggregated_list(request=request)

    for zone, instances_scoped_list in zones:
        if instances_scoped_list.instances:
            for instance in instances_scoped_list.instances:
                instance_name = instance.name
                vm_creation_time = instance.creation_timestamp  # VM creation timestamp
                vm_zone = zone.split('/')[-1]  # Extract zone from the zone path
                
                # Get service account details
                service_accounts = []
                if instance.service_accounts:
                    for service_account in instance.service_accounts:
                        service_accounts.append(service_account.email)
                service_account_details = ', '.join(service_accounts)  # Join service accounts if there are multiple
                
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
                        
                        # Fetch image labels and creation timestamp
                        try:
                            image_info = image_client.get(project=image_project, image=image_name)
                            labels = dict(image_info.labels) if image_info.labels else {}
                            deprecation_status = image_info.deprecated
                            image_creation_time = image_info.creation_timestamp  # Image creation timestamp
                        except Exception as e:
                            print(f"Error fetching image info for {image_name}: {e}")
                            labels = {}
                            deprecation_status = None
                            image_creation_time = None
                        
                        # Determine compliance status
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
                            "VM Creation Time": vm_creation_time,
                            "VM Zone": vm_zone,
                            "VM Service Account": service_account_details,
                            "Source Image": image_name,
                            "Image Creation Time": image_creation_time,
                            "Labels": json.dumps(labels),
                            "Compliant Status": compliant_val,
                            "Deprecation Status": deprecation_status,
                            "Project Owner": project_owner
                        })
                    else:
                        print(f"No source image found for disk {disk_name} in project {project_id}")
    
    return results

def save_to_excel(data, output_file):
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
    projects = ["zjmqcnnb-gf42-i38m-a28a-y3gmil", "qeoomwdf-p6lv-89z3-jh5z-7u791i"]  # Replace with your actual project IDs
    bucket_name = "rsingal-gcp-build-bucket"  # Replace with your GCS bucket name
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
