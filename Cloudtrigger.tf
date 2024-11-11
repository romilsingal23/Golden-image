# Define your variables (for example, project ID and bucket name)
variable "project_id" {
  type    = string
  default = "your-project-id"
}

variable "bucket_name" {
  type    = string
  default = "your-source-bucket"
}

# Cloud Build Trigger resource
resource "google_cloudbuild_trigger" "image_build_trigger" {
  project      = var.project_id
  name         = "image-build-trigger"
  description  = "Trigger to build images with substitution variables"
  trigger_template {
    branch_name = "main"
    repo_name   = "your-repo-name"
  }

  # Define your substitutions
  substitutions = {
    "_IMAGE_NAME"   = "default-image-name"      # Placeholder; will be replaced dynamically
    "_IMAGE_FAMILY" = "default-image-family"    # Placeholder; will be replaced dynamically
    "_SSH_USERNAME" = "default-user"            # Placeholder; will be replaced dynamically
    "_DATE_CREATED" = "default-date"            # Placeholder; will be replaced dynamically
  }

  # Build steps or configuration
  filename = "cloudbuild.yaml"
}

# Example to output the build trigger ID, if needed
output "build_trigger_id" {
  value = google_cloudbuild_trigger.image_build_trigger.id
}
