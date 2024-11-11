# Load the template file (images.json)
data "template_file" "substitutions" {
  template = file("path/to/images.json")
}

# Parse the JSON into a local map
locals {
  images_data = jsondecode(data.template_file.substitutions.rendered)
  
  # Extract GCP-specific data
  gcp_substitutions = local.images_data["gcp"]
}

# Cloud Build Trigger with dynamic substitutions for GCP
resource "google_cloudbuild_trigger" "image_build_trigger" {
  project     = var.project_id
  name        = "image-build-trigger"
  description = "Trigger to build GCP images with dynamic substitution variables"
  trigger_template {
    branch_name = "main"
    repo_name   = "your-repo-name"
  }

  substitutions = {
    "_IMAGE_NAME"   = local.gcp_substitutions["image_name"]
    "_IMAGE_FAMILY" = local.gcp_substitutions["image_family"]
    "_SSH_USERNAME" = local.gcp_substitutions["ssh_username"]
    "_DATE_CREATED" = local.gcp_substitutions["date_created"]
  }

  filename = "cloudbuild.yaml"
}
