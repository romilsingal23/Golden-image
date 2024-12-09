def list_projects_in_organization_and_folders(org_id):
    folders_client = resourcemanager_v3.FoldersClient()
    projects_client = resourcemanager_v3.ProjectsClient()
    all_projects = []

    # Retrieve projects directly under the organization
    org_request = resourcemanager_v3.SearchProjectsRequest(query=f"parent.type:organization parent.id:{org_id}")
    all_projects.extend([project.project_id for project in projects_client.search_projects(request=org_request) if project.state.name == "ACTIVE"])

    # Retrieve folders under the organization
    folders = folders_client.search_folders(request={"parent": f"organizations/{org_id}"})
    for folder in folders:
        folder_id = folder.name.split("/")[-1]
        folder_request = resourcemanager_v3.SearchProjectsRequest(query=f"parent.type:folder parent.id:{folder_id}")
        all_projects.extend([project.project_id for project in projects_client.search_projects(request=folder_request) if project.state.name == "ACTIVE"])

    return all_projects
