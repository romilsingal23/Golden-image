import os
import json
import base64
from google.cloud import artifactregistry_v1  
from logger.gcp_logging import initialize_logger, initialize_cloud_logger
import installer.install_defender_vm as defender_vm
import installer.install_defender_cluster as defender_cluster

logger = initialize_logger('compute-scan-logger')
cloud_logger = initialize_cloud_logger('compute-scan-custom-logger')

def delete_images(project, logger):  
    logger.info("Deleting images from Artifact Registry")
    client = artifactregistry_v1.ArtifactRegistryClient()  
    location = "us-central1"  
    repository = "gcf-artifacts"  
    parent = f"projects/{project}/locations/{location}/repositories/{repository}"  

    image_default = f"{parent}/packages/{project.replace('-', '--')}__us--central1__compute--scan--manager--{project.replace('-', '--')}"

    images = [image_default, f"{image_default}%2Fcache"]
    flag = False
    # List the packages in the repository
    for package in client.list_packages(parent=parent):
        if package.name in images:
            logger.info(f"Package: {package.name} started deleting....")
            # Initialize request argument(s)
            request = artifactregistry_v1.DeletePackageRequest(
                name=package.name,
            )

            # Make the request
            operation = client.delete_package(request=request) 
            flag = True
            logger.info(f"Package deleted successfully.")
            
    if not flag:
        logger.info("No images found to delete.")
