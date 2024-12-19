# Service Account for Cloud Function
resource "google_service_account" "scheduler_sa" {
  project      = var.project_id
  account_id   = "${local.namespace-}build-trigger-sa"
  display_name = "Build Trigger Service Account"
}

resource "google_project_iam_member" "cloudbuild_function" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

resource "google_project_iam_member" "cloud_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

#####################################################################################################

resource "google_project_iam_binding" "share_image" {
  count       = var.environment == "prod" ? 1 : 0
  project = var.project_id
  role    = "roles/compute.imageUser"
  members = ["domain:optum.com"]
}

#####################################################################################################
resource "google_service_account" "cloud_build" {
  project      = var.project_id
  account_id   = "${local.namespace-}cloud-build-sa"
  display_name = "Cloud Build Service Account"
}

resource "google_project_iam_member" "cloudbuild_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloudbuild_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloudbuild_trigger" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloudbuild_secrets_manager" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloudbuild_service_account" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloudbuild_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloudbuild_iap" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloudbuild_iap1" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member = "group:GCP_${replace(var.project_id,"-","_")}_Owners_JIT@groups.optum.com"
}

resource "google_project_iam_member" "cloudbuild_instance_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# # Getting the AWS iam user details from aws secrets manager and storing then in GCP secrets Manager

data "aws_secretsmanager_secret" "iam-access-key" {
  name = "${local.namespaces_}iam_access_key"
}

data "aws_secretsmanager_secret" "iam-secret" {
  name = "${local.namespaces_}iam_secret_key"
}

data "aws_secretsmanager_secret_version" "iam-access-key" {
  secret_id = data.aws_secretsmanager_secret.iam-access-key.id
}

data "aws_secretsmanager_secret_version" "iam-secret" {
  secret_id = data.aws_secretsmanager_secret.iam-secret.id
}

resource "google_secret_manager_secret" "aws-iam-access-key" {
  secret_id = "${local.namespaces-}access-key"
  replication {
    user_managed {
      replicas {
        location = "us-east1"
      }
    }
  }
}

resource "google_secret_manager_secret_version" "aws-iam-access-key" {
  secret = google_secret_manager_secret.aws-iam-access-key.id

  secret_data = data.aws_secretsmanager_secret_version.iam-access-key.secret_string
}

resource "google_secret_manager_secret" "aws-iam-secret-key" {
  secret_id = "${local.namespaces-}secret-key"
  replication {
    user_managed {
      replicas {
        location = "us-east1"
      }
    }
  }
}

resource "google_secret_manager_secret_version" "aws-iam-secret-key" {
  secret = google_secret_manager_secret.aws-iam-secret-key.id

  secret_data = data.aws_secretsmanager_secret_version.iam-secret.secret_string
}
