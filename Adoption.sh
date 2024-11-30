def get_vm_creator(logging_client, project_id, vm_name):
    """Fetches the creator of the VM from Cloud Audit Logs."""
    query = (
        f'resource.type="gce_instance" '
        f'AND protoPayload.methodName="v1.compute.instances.insert" '
        f'AND resource.labels.instance_id:{vm_name}'
    )
    try:
        print(f"Running query: {query}")  # Debugging the query
        entries = logging_client.list_entries(order_by=logging.DESCENDING, filter_=query)
        for entry in entries:
            print(f"Log entry: {entry}")  # Debugging log entry content
            if entry.proto_payload:
                authentication_info = entry.proto_payload.get('authenticationInfo', {})
                actor = authentication_info.get('principalEmail')
                if actor:
                    print(f"Found creator: {actor}")  # Debug output for found creator
                    return actor
        print(f"No creator found for VM: {vm_name}")  # Debug output when no creator is found
    except Exception as e:
        print(f"Error fetching creator for VM {vm_name}: {e}")
    return "Unknown"
