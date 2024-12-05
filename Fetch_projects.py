from google.cloud import resourcemanager_v3

def fetch_projects():
    """Fetch all projects the service account has access to using the Resource Manager API."""
    client = resourcemanager_v3.ProjectsClient()
    projects = []

    for project in client.list_projects():
        if project.state == resourcemanager_v3.Project.State.ACTIVE:
            projects.append(project.project_id)
    
    return projects

# Test the function
if __name__ == "__main__":
    projects = fetch_projects()
    print("Projects:", projects)
