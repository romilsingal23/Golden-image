from google.cloud import resourcemanager_v3

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

def main(request=None):
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
        
        output_file = "vm_image_labels.xlsx"
        all_results = []

        # Process each project
        for project in projects:
            logger.info(f"Processing Project: {project}")
            project_data = fetch_instance_data(project)
            all_results.extend(project_data)

        # Save results to Excel
        df = pd.DataFrame(all_results)
        buffer = io.BytesIO()
        df.to_excel(buffer, index=False)
        buffer.seek(0)

        # Upload the file to GCS
        upload_to_gcs(output_file, bucket_name, "vm_image_labels.xlsx", buffer)
        return {"message": "File uploaded successfully!"}, 200
    except Exception as e:
        logger.error("Error in main function: %s", e)
        return {"error": str(e)}, 500
