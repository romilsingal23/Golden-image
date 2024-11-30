def get_vm_creator(logging_client, project_id, vm_name):
    query = (
        f'resource.type="gce_instance" '
        f'AND protoPayload.methodName="v1.compute.instances.insert" '
        f'AND resource.labels.instance_id="{vm_name}"'
    )
    try:
        print(f"Running query: {query}")
        entries = list(logging_client.list_entries(order_by=logging.DESCENDING, filter_=query))
        print(f"Entries found: {len(entries)}")  # Debug number of entries

        for entry in entries:
            print(f"Entry details: {entry.to_api_repr()}")  # Print raw log entry
            if entry.proto_payload:
                authentication_info = entry.proto_payload.get('authenticationInfo', {})
                actor = authentication_info.get('principalEmail')
                if actor:
                    print(f"Found creator: {actor}")
                    return actor
        print(f"No creator found for VM: {vm_name}")
    except Exception as e:
        print(f"Error fetching creator for VM {vm_name}: {e}")
    return "Unknown"
