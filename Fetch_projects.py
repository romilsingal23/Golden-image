import logging
from google.cloud import resourcemanager_v3
from google.auth import default

# Initialize logging
logging.basicConfig(level=logging.DEBUG)  # More detailed logging

def fetch_projects():
    """Fetch the accessible projects for the service account or user."""
    try:
        # Get default credentials and the project
        credentials, project = default()
        
        logging.debug(f"Default credentials acquired: {credentials}")
        logging.debug(f"Active project: {project}")

        # Initialize the client with the credentials
        client = resourcemanager_v3.ProjectsClient(credentials=credentials)
        projects = []

        # Request to list projects
        request = resourcemanager_v3.ListProjectsRequest()
        for project in client.list_projects(request=request):
            logging.debug(f"Project found: {project}")
            if project.state == resourcemanager_v3.Project.State.ACTIVE:
                projects.append(project.project_id)
                logging.debug(f"Active project: {project.project_id}")

        logging.info(f"Fetched {len(projects)} active projects.")
        return projects
    except Exception as e:
        # Log the full error message and stack trace for debugging
        logging.error(f"Error fetching projects: {e}", exc_info=True)
        return []

if __name__ == "__main__":
    projects = fetch_projects()
    print("Accessible Projects:", projects)
