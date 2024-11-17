# Service Account for Cloud Function
resource "google_service_account" "build_trigger" {
  project = var.project_id
  account_id   = "build-trigger-sa"
  display_name = "Build Trigger Service Account"
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

resource "google_project_iam_member" "cloudbuild_storage" {
  project = var.project_id
  role    = "roles/compute.imageAdmin"
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

resource "google_project_iam_member" "cloudbuild_function" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.build_trigger.email}"
}
