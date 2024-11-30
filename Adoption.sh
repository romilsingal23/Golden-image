def get_vm_creator(logging_client, project_id, vm_name):
    """Fetches the creator of the VM from Cloud Audit Logs."""
    query = f'resource.type="gce_instance" AND protoPayload.methodName="compute.instances.insert" AND protoPayload.resourceName:"{vm_name}"'
    try:
        # Fetch the log entries using the query
        entries = logging_client.list_entries(order_by=logging.DESCENDING, filter_=query)
        
        # Iterate through the log entries
        for entry in entries:
            # Log entry payload inspection
            print(f"Log entry: {entry}")
            
            # Extract `protoPayload` from the log entry
            if hasattr(entry, "protoPayload") and entry.protoPayload:
                proto_payload = entry.protoPayload
                
                # Extract `authenticationInfo` from `protoPayload`
                if hasattr(proto_payload, "authenticationInfo") and proto_payload.authenticationInfo:
                    actor = proto_payload.authenticationInfo.principalEmail
                    print(f"Found creator: {actor}")  # Debug output
                    return actor
        
        # If no creator is found, return unknown
        print(f"No creator found for VM: {vm_name}")  # Debug output
        return "Unknown"

    except Exception as e:
        # Log the exception for debugging
        print(f"Error fetching creator for VM {vm_name}: {e}")
        return "Unknown"
