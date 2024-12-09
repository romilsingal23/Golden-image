from google.cloud import resourcemanager_v3

def list_all_projects_in_organization(org_id):
    client = resourcemanager_v3.ProjectsClient()
    folder_client = resourcemanager_v3.FoldersClient()

    # Function to fetch all subfolders recursively
    def get_subfolders(parent):
        subfolders = []
        request = resourcemanager_v3.ListFoldersRequest(parent=parent)
        for folder in folder_client.list_folders(request=request):
            subfolders.append(folder.name)
            # Recursively fetch nested subfolders
            subfolders.extend(get_subfolders(folder.name))
        return subfolders

    # Start by fetching top-level subfolders in the organization
    parent = f"organizations/{org_id}"
    all_folders = get_subfolders(parent)

    # Include the root organization in the search
    all_parents = [parent] + all_folders

    # Collect all projects under each parent (organization and subfolders)
    all_projects = []
    for parent in all_parents:
        request = resourcemanager_v3.SearchProjectsRequest(query=f"parent:{parent}")
        all_projects.extend([
            project.project_id for project in client.search_projects(request=request)
            if project.state.name == "ACTIVE"
        ])
    return all_projects
