import os
import json
from flask import Flask, jsonify, request
from google.cloud import compute_v1, storage
import pandas as pd

app = Flask(__name__)

# Fetch instance data function
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
                            "Deprecation Status": deprecation_status
                        })
                    else:
                        print(f"No source image found for disk {disk_name} in project {project_id}")
    
    return results

# Save data to Excel
def save_to_excel(data, output_file):
    df = pd.DataFrame(data)
    df.to_excel(output_file, index=False)
    print(f"Data saved to {output_file}")

# Upload file to Google Cloud Storage
def upload_to_gcs(file_path, bucket_name, destination_blob_name):
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob_name)
        blob.upload_from_filename(file_path)
        print(f"File uploaded to gs://{bucket_name}/{destination_blob_name}")
    except Exception as e:
        print(f"Error uploading file to GCS: {e}")

# Main function to export VM image labels
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

# Flask route for triggering the export
@app.route("/run", methods=["POST"])
def run_export():
    try:
        export_vm_image_labels()
        return jsonify({"message": "Export completed successfully"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# Health check route
@app.route("/")
def health_check():
    return jsonify({"status": "running"}), 200

if __name__ == "__main__":
    # Get the PORT environment variable
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
