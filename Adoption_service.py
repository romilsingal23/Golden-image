def main(request=None):
    try:
        projects = list_projects_in_organization(organization_id)
        all_results, all_employee_ids = [], []

        for project in projects:
            try:
                logger.info(f"Processing Project: {project}")
                project_data, employee_ids = fetch_instance_data(project)
                all_results.extend(project_data)
                all_employee_ids.extend(employee_ids)
            except Exception as e:
                # Log the error and continue to the next project
                logger.error(f"Error processing project {project}: {e}")
                continue

        # Deduplicate employee IDs and fetch email mappings
        unique_employee_ids = list(set(all_employee_ids))
        try:
            user_email_response = get_email_ids_from_employeeIds(unique_employee_ids)
            for obj in all_results:
                obj["email"] = user_email_response.get(obj.get("employeeid"))
        except Exception as e:
            logger.error(f"Error retrieving email mappings: {e}")

        # Convert results to a DataFrame and save to Excel
        if all_results:
            df = pd.DataFrame(all_results)
            buffer = io.BytesIO()
            df.to_excel(buffer, index=False)
            buffer.seek(0)

            upload_to_gcs("vm_image_labels.xlsx", bucket_name, "vm_image_labels.xlsx", buffer)
            logger.info("File uploaded successfully!")
            return {"message": "File uploaded successfully!"}, 200
        else:
            logger.warning("No results to process. Exiting.")
            return {"message": "No data processed"}, 204

    except Exception as e:
        logger.error("Error in main function: %s", e)
        return {"error": str(e)}, 500

if __name__ == "__main__":
    main()
