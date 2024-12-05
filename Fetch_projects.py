from google.cloud import resourcemanager_v3
from google.auth import default
import logging

logging.basicConfig(level=logging.DEBUG)

def fetch_projects():
    try:
        credentials, project = default()
        logging.info(f"Using credentials: {credentials}")
        logging.info(f"Default project: {project}")

        # Initialize the client
        client = resourcemanager_v3.ProjectsClient(credentials=credentials)
        request = resourcemanager_v3.ListProjectsRequest()

        logging.debug(f"ListProjectsRequest: {request}")

        # Fetch projects
        projects = []
        for proj in client.list_projects(request=request):
            logging.info(f"Found project: {proj.project_id}")
            if proj.state == resourcemanager_v3.Project.State.ACTIVE:
                projects.append(proj.project_id)

        return projects
    except Exception as e:
        logging.error(f"Error occurred: {e}", exc_info=True)
        return []

if __name__ == "__main__":
    projects = fetch_projects()
    print("Accessible Projects:", projects)
