def fetch_projects():
    """Fetch the accessible projects for the service account."""
    try:
        client = resourcemanager_v3.ProjectsClient()
        projects = []

        for project in client.list_projects():
            if project.state == resourcemanager_v3.Project.State.ACTIVE:
                projects.append(project.project_id)

        return projects
    except Exception as e:
        logging.error(f"Error fetching projects: {e}")
        return []
