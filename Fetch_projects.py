from typing import Dict, List, Union
from google.cloud import resourcemanager_v3

def projects_in_folder(folder_id: str) -> List[str]:
    """
    Retrieves a list of active project names within a specified folder.

    Args:
        folder_id (str): The ID of the folder.

    Returns:
        List[str]: A list of active project names within the folder.
    """
    client = resourcemanager_v3.ProjectsClient()
    query = f'parent.type:folder parent.id:{folder_id}'
    request = resourcemanager_v3.SearchProjectsRequest(query=query)
    response = client.search_projects(request=request)

    projects = []
    for project in response:
        if project.state == resourcemanager_v3.Project.State.ACTIVE:
            projects.append(project.display_name)

    return projects

def get_folder_hierarchy(
    parent_id: str = "organizations/12345",
    hierarchy: Union[Dict[str, Union[str, List[str]]], None] = None,
) -> Dict[str, Union[str, List[str]]]:
    """
    Retrieves the folder hierarchy of the Google Cloud resource structure starting from the specified parent ID.

    Args:
        parent_id (str): The ID of the parent resource to start the hierarchy from.
                         Defaults to "organizations/12345".
        hierarchy (Union[Dict[str, Union[str, List[str]]], None]): The dictionary representing the folder hierarchy.
                                                                   Defaults to None.

    Returns:
        Dict[str, Union[str, List[str]]]: A dictionary representing the folder hierarchy of the resource structure.
                                          The keys represent folder names, and the values can either be lists of
                                          project names within a folder or sub-hierarchies (dictionaries).
    """
    if hierarchy is None:
        hierarchy = {}

    client = resourcemanager_v3.FoldersClient()
    request = resourcemanager_v3.ListFoldersRequest(parent=parent_id)
    response = client.list_folders(request=request)

    for folder in response:
        folder_id = folder.name.split('/')[-1]
        folder_name = folder.display_name
        projects = projects_in_folder(folder_id)

        if projects:
            hierarchy[folder_name] = projects
            pass
        else:
            sub_hierarchy = get_folder_hierarchy(parent_id=folder.name, hierarchy={})
            if sub_hierarchy:
                hierarchy[folder_name] = sub_hierarchy

    return hierarchy

folder_hierarchy_data = get_folder_hierarchy()
print(folder_hierarchy_data)
