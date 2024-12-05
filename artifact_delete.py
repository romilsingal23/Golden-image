import os
import json
import logging
import traceback
from google.cloud import artifactregistry_v1

# Initialize logging
logger = logging.getLogger()
logging.basicConfig(level=logging.INFO)

project_id = os.getenv('PROJECT_ID', "zjmqcnnb-gf42-i38m-a28a-y3gmil")  # Google Cloud Project ID

def delete_images(project, logger):  
    logger.info("Deleting images from Artifact Registry")
    client = artifactregistry_v1.ArtifactRegistryClient()  
    location = "us-east1"  
    repository = "gcf-artifacts"  
    parent = f"projects/{project}/locations/{location}/repositories/{repository}"  

    flag = False
    # List the packages in the repository
    for package in client.list_packages(parent=parent):
        if 'function' in package.name:
            print("package.name", package.name)
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
        # logger.info("No images found to delete.")
        print("No images found to delete.")
    return {"statusCode": 200, "message": "Artifact Images deleted successfully"}
 
def main(request=None):
    """HTTP Cloud Function to delete images from Artifact Registry."""
    try:
        logger.info("Starting the main function for deleting images from Artifact Registry")
        response = delete_images(project_id, logger)
        logger.info(f"Function executed successfully. Response: {response}")
        return ( json.dumps(response), response.get("statusCode", 500), {"Content-Type": "application/json"}, )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        logger.error("".join(traceback.format_exc()))  # Log full traceback
        return ( json.dumps({"error": "Internal Server Error"}), 500, {"Content-Type": "application/json"},)

if __name__ == "__main__":
    main()
