import datetime
from google.cloud import compute_v1

def lifecycle_handler(request):
    # Initialize clients
    image_client = compute_v1.ImagesClient()
    instance_client = compute_v1.InstancesClient()
    disk_client = compute_v1.DisksClient()
    project_id = "consumer-project-431315"
    zone = "us-east1-b"
    now = datetime.datetime.now(datetime.timezone.utc)
    
    # Define lifecycle durations
    obsolete_after_days = 30
    delete_after_days = 365
    vm_delete_after_days = 30  # Delete old VMs after 30 days
    
    # Step 1: Manage Image Lifecycle
    for image in image_client.list(project=project_id):
        creation_time = image.creation_timestamp
        creation_date = datetime.datetime.strptime(creation_time, '%Y-%m-%dT%H:%M:%S.%f%z')
        age_in_days = (now - creation_date).days

        if age_in_days > delete_after_days:
            # Mark image as deleted
            print(f"Marking image {image.name} as DELETED")
            image_client.deprecate_unary(
                project=project_id,
                image=image.name,
                deprecated_resource=compute_v1.DeprecationStatus(
                    state=compute_v1.DeprecationStatus.State.DELETED
                )
            )
        elif age_in_days > obsolete_after_days:
            # Mark image as obsolete
            print(f"Marking image {image.name} as OBSOLETE")
            image_client.deprecate_unary(
                project=project_id,
                image=image.name,
                deprecated_resource=compute_v1.DeprecationStatus(
                    state=compute_v1.DeprecationStatus.State.OBSOLETE
                )
            )
    
    # Step 2: Clean Up Old VMs
    for instance in instance_client.list(project=project_id, zone=zone):
        creation_time = instance.creation_timestamp
        creation_date = datetime.datetime.strptime(creation_time, '%Y-%m-%dT%H:%M:%S.%f%z')
        age_in_days = (now - creation_date).days

        if age_in_days > vm_delete_after_days and "golden-vm" in instance.tags.items:
            # Delete old VMs
            print(f"Deleting old VM: {instance.name}")
            instance_client.delete(project=project_id, zone=zone, instance=instance.name)

            # Optionally, clean up disks attached to the VM
            for disk in instance.disks:
                if disk.boot and disk.auto_delete:
                    print(f"Deleting associated boot disk: {disk.source}")
                    disk_name = disk.source.split('/')[-1]
                    disk_client.delete(project=project_id, zone=zone, disk=disk_name)

    return "Image and VM cleanup completed."
