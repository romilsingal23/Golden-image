resource "google_cloudbuild_trigger" "image_build_trigger" {
  project     = var.project_id
  name        = "scheduled-image-build-trigger"
  description = "Scheduled trigger to build images with dynamic substitution variables"

  manual_trigger {}

  substitutions = {
    "_IMAGE_NAME"   = local.substitutions["image_name"]
    "_IMAGE_FAMILY" = local.substitutions["image_family"]
    "_SSH_USERNAME" = local.substitutions["ssh_username"]
    "_DATE_CREATED" = local.substitutions["date_created"]
  }

  filename = "cloudbuild.yaml"
}

resource "google_cloud_scheduler_job" "scheduled_trigger_job" {
  name        = "scheduled-trigger-job"
  description = "Scheduled job to trigger Cloud Build on a cron schedule"
  schedule    = "0 0 * * *" # Cron expression (e.g., every day at midnight)
  time_zone   = "UTC"

  http_target {
    uri = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/triggers/${google_cloudbuild_trigger.image_build_trigger.id}:run"
    http_method = "POST"
    headers = {
      "Authorization" = "Bearer ${data.google_iam_access_token.cloud_build_access_token.access_token}"
    }
  }
}

data "google_iam_access_token" "cloud_build_access_token" {
  scopes = ["https://www.googleapis.com/auth/cloud-platform"]
}
