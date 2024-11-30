gcloud logging read \
    'resource.type="gce_instance" AND protoPayload.methodName="v1.compute.instances.insert"' \
    --project=YOUR_PROJECT_ID \
    --format="json(protoPayload.authenticationInfo.principalEmail, resource.labels.instance_id, protoPayload.request)" \
    --limit 10
