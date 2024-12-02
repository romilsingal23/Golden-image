
# 1. Create the Tag Key
resource "google_tags_tag_key" "trusted_image_key" {
  short_name  = "enforce-trusted-images"
  description = "Tag for enforcing trusted image usage"
  parent      = "organizations/YOUR_ORGANIZATION_ID" # Replace with your Organization ID
}

# 2. Create the Tag Value
resource "google_tags_tag_value" "enabled" {
  short_name  = "enabled"
  description = "Enable enforcement of trusted images"
  parent      = google_tags_tag_key.trusted_image_key.name
}

# 3. Grant Tag User Role (IAM)
resource "google_project_iam_member" "project_tag_user" {
  project = "your-project-id" # Replace with your project ID
  role    = "roles/resourcemanager.tagUser"
  member  = "user:your-email@example.com" # Replace with the email of the user or group
}

# 4. Bind the Tag to the Project
resource "google_tags_tag_binding" "project_tag" {
  parent    = "projects/your-project-id" # Replace with your project ID
  tag_value = google_tags_tag_value.enabled.name
}

# 5. Set Org Policy for Trusted Images
resource "google_org_policy" "trusted_image_policy" {
  constraint = "constraints/compute.trustedImageProjects"
  parent     = "projects/your-project-id" # Replace with your project or folder ID

  policy {
    enforce = true

    # Allow if tag 'enforce-trusted-images' is set to 'enabled'
    rules {
      condition {
        expression = "resource.matchTag('enforce-trusted-images', 'enabled')"
      }
      allow_all = true
    }

    # Deny if the tag is missing or not set to 'enabled'
    rules {
      condition {
        expression = "!resource.matchTag('enforce-trusted-images', 'enabled')"
      }
      deny_all = true
    }
  }
}
