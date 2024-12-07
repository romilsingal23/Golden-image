from google.cloud import resourcemanager_v3
from loguru import logger
import os

# Function to list all projects in an organization
def list_projects_in_organization(organization_id):
    try:
        client = resourcemanager_v3.ProjectsClient()
        org_name = f"organizations/{organization_id}"
        request = resourcemanager_v3.ListProjectsRequest(parent=org_name)

        projects = []
        for project in client.list_projects(request=request):
            if project.state == resourcemanager_v3.Project.State.ACTIVE:
                projects.append(project.project_id)

        logger.info(f"Found {len(projects)} active projects in organization {organization_id}")
        return projects
    except Exception as e:
        logger.error(f"Error while listing projects in organization {organization_id}: {e}")
        return []

def main():
    try:
        # Replace with your organization ID
        organization_id = os.getenv("ORGANIZATION_ID")
        if not organization_id:
            raise ValueError("ORGANIZATION_ID environment variable is not set.")
        
        # Fetch all projects in the organization
        projects = list_projects_in_organization(organization_id)
        if not projects:
            logger.warning("No active projects found in the organization.")
            return {"message": "No active projects found in the organization"}, 404

        # Return the list of projects
        return {"projects": projects}, 200
    except Exception as e:
        logger.error("Error in main function: %s", e)
        return {"error": str(e)}, 500

if __name__ == "__main__":
    result = main()
    print(result)
