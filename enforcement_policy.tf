name: "organizations/ORG_ID/policies/compute.trustedImageProjects"
spec:
  rules:
    - condition:
        expression: "resource.matchTag('enforce-trusted-images', 'enabled')"
        title: "Enforce Trusted Images"
        description: "Restrict VM creation to trusted images when the tag is applied."
      allowAll: true
    - condition:
        expression: "!resource.matchTag('enforce-trusted-images', 'enabled')"
        title: "Deny VM Creation Without Trusted Image Enforcement"
        description: "Deny VM creation if the tag is not set."
      denyAll: true
  inheritFromParent: true
  reset: false
  etag: "etag_value" # Replace with the actual etag from your current policy, if updating.
  updateTime: "2023-12-02T00:00:00Z" # Replace with the actual time of update.
