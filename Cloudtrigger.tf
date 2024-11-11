# Load the template file (images.json)
data "template_file" "substitutions" {
  template = file("path/to/images.json")
}

# Parse the JSON into a local map
locals {
  images_data = jsondecode(data.template_file.substitutions.rendered)

  # Extract GCP-specific data for all OS types (RHEL_8, RHEL_9, Windows_22, etc.)
  gcp_images = local.images_data["gcp"]
}

# Cloud Build Trigger for each OS type
resource "google_cloudbuild_trigger" "image_build_trigger" {
  for_each = local.gcp_images

  project     = var.project_id
  name        = "image-build-trigger-${each.key}"
  description = "Trigger to build the ${each.key} image with dynamic substitution variables"
  trigger_template {
    branch_name = "main"
    repo_name   = "your-repo-name"
  }

  substitutions = {
    "_IMAGE_NAME"        = each.value["image_name"]
    "_IMAGE_FAMILY"      = each.value["image_family"]
    "_IMAGE_PROJECT"     = each.value["image_project"]
    "_ARCHITECTURE"      = each.value["architecture"]
    "_DEVICE_TYPE"       = each.value["device_type"]
    "_ROOT_VOLUME"       = each.value["root_volume"]
    "_SSH_USER"          = each.value["ssh_user"]
    "_VIRTUALIZATION_TYPE" = each.value["virtualization_type"]
  }

  filename = "cloudbuild.yaml"
}
