from google.cloud import resourcemanager_v3

def fetch_all_projects(org_id):
    projects_client = resourcemanager_v3.ProjectsClient()
    folders_client = resourcemanager_v3.FoldersClient()
    folders = folders_client.search_folders(request={"query": f"parent=organizations/{org_id}"})
    all_projects = []
    for folder in folders:
        all_projects.extend(fetch_projects_in_folder(folder.name, folders_client, projects_client))
    return all_projects

def fetch_projects_in_folder(folder_id, folders_client, projects_client):
    projects = []
    for project in projects_client.list_projects(parent=folder_id):
        projects.append({
            "project_id": project.project_id,
            "display_name": project.display_name,
            "parent": folder_id
        })
    subfolders = folders_client.list_folders(parent=folder_id)
    for subfolder in subfolders:
        projects.extend(fetch_projects_in_folder(subfolder.name, folders_client, projects_client))
    return projects

if __name__ == "__main__":
    ORGANIZATION_ID = "123456789"
    projects = fetch_all_projects(ORGANIZATION_ID)
    for project in projects:
        print(f"Project ID: {project['project_id']}, Name: {project['display_name']}, Parent: {project['parent']}")
