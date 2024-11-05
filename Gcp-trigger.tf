provider "google" {
  project = var.project_id
  region  = var.region
}

# IAM Policy for GCP Services
resource "google_project_iam_member" "cloudbuild_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.build_trigger.email}"
}

resource "google_project_iam_member" "cloudbuild_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.build_trigger.email}"
}

resource "google_project_iam_member" "cloudbuild_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.build_trigger.email}"
}

resource "google_project_iam_member" "cloudbuild_trigger" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.build_trigger.email}"
}

# Service Account for Cloud Function
resource "google_service_account" "build_trigger" {
  account_id   = "build-trigger"
  display_name = "Build Trigger Service Account"
}

# Cloud Storage Bucket
resource "google_storage_bucket" "supported_images" {
  name          = "${var.namespace}-supported-images"
  location      = var.region
  force_destroy = true
}

resource "google_storage_bucket_object" "supported_images" {
  bucket = google_storage_bucket.supported_images.name
  name   = "supported_images.json"
  source = "${path.module}/../../supported_images.json"
}

# Archive the Cloud Function Source Code
data "archive_file" "build_trigger" {
  type        = "zip"
  source_file = "${path.module}/../../python/gcp_build/build_trigger/main.py"
  output_path = "${path.root}/build_trigger.zip"
}

# Cloud Function
resource "google_cloudfunctions_function" "build_trigger" {
  name        = "${var.build_name}_trigger"
  runtime     = "python39"
  region      = var.region
  source_archive_bucket = google_storage_bucket.supported_images.name
  source_archive_object = google_storage_bucket_object.supported_images.name
  entry_point = "main.lambda_handler"
  trigger_http = false

  environment_variables = {
    PROJECT_NAME              = var.build_name
    SUPPORTED_IMAGES_BUCKET   = google_storage_bucket.supported_images.name
  }

  service_account_email = google_service_account.build_trigger.email
  available_memory_mb   = 256
  timeout               = 180
}

# Cloud Scheduler Job for Triggering Cloud Function
resource "google_cloud_scheduler_job" "build_trigger" {
  name        = "${var.build_name}_trigger"
  description = "Nightly trigger for building GCP Golden Images"
  schedule    = "0 5 * * *"  # Daily at 5 AM UTC
  time_zone   = "UTC"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.build_trigger.https_trigger_url
    oidc_token {
      service_account_email = google_service_account.build_trigger.email
    }
  }
}

# Cloud Build Trigger
resource "google_cloudbuild_trigger" "build_trigger" {
  name = "${var.build_name}_trigger"
  filename = "cloudbuild.yaml"

  included_files = ["**"]
  substitutions = {
    _PROJECT_NAME              = var.build_name
    _SUPPORTED_IMAGES_BUCKET   = google_storage_bucket.supported_images.name
  }
}

# Logging Configuration
resource "google_logging_project_sink" "build_trigger" {
  name        = "${var.build_name}_trigger"
  destination = "storage.googleapis.com/${google_storage_bucket.supported_images.name}"
  filter      = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.build_trigger.name}\""
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "namespace" {
  description = "Namespace for resources"
  type        = string
  default     = "my-app"
}

variable "build_name" {
  description = "Build name for the trigger"
  type        = string
  default     = "gcp_build"
}
