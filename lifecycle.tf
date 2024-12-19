data "archive_file" "lifecycle" {
  type        = "zip"
  source_dir  = "${path.module}/lifecycle_function"
  output_path = "${path.module}/lifecycle.zip"
}

resource "google_storage_bucket_object" "lifecycle" {
  name   = "lifecycle_${uuid()}.zip"
  bucket = google_storage_bucket.gcp_build.name
  source = data.archive_file.lifecycle.output_path
}

resource "google_cloudfunctions_function" "obsolete_function" {
  name                = "${local.namespaces_}obsolete_function"
  project             = var.project_id
  region              = var.region
  runtime             = "python312"
  available_memory_mb = 512

  source_archive_bucket        = google_storage_bucket.gcp_build.name
  source_archive_object        = google_storage_bucket_object.lifecycle.name
  trigger_http                 = true
  https_trigger_security_level = "SECURE_ALWAYS"
  entry_point                  = "main"
  service_account_email        = google_service_account.lifecycle_sa.email
  build_environment_variables = {
    GOOGLE_FUNCTION_SOURCE = "obsolete.py"
  }
  environment_variables = {
    dynamodb_table = data.aws_dynamodb_table.common_image_table.name
    PROJECT_ID     = var.project_id
    aws_access_key = "${local.namespaces-}access-key"
    aws_secret_key = "${local.namespaces-}secret-key"
    image_families = "${local.namespaces-}gim-rhel-9,${local.namespaces-}gim-windows-2022"
  }
  depends_on = [google_storage_bucket_object.lifecycle]

}

resource "google_cloud_scheduler_job" "obsolete_job" {
  name        = "${local.namespaces_}obsolete_job"
  description = "Job to run the obsolete_function"
  schedule    = "0 9 * * 0"
  time_zone   = "UTC"

  http_target {
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/${google_cloudfunctions_function.build_function.name}"
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
    headers = {
      "Content-Type" = "application/json"
    }
  }
}

resource "google_cloudfunctions_function" "delete_function" {
  name    = "${local.namespaces_}delete_function"
  project = var.project_id
  region  = var.region
  runtime = "python39"

  available_memory_mb          = 512
  source_archive_bucket        = google_storage_bucket.gcp_build.name
  source_archive_object        = google_storage_bucket_object.lifecycle.name
  trigger_http                 = true
  https_trigger_security_level = "SECURE_ALWAYS"
  entry_point                  = "main"
  service_account_email        = google_service_account.lifecycle_sa.email
  build_environment_variables = {
    GOOGLE_FUNCTION_SOURCE = "delete.py"
  }
  environment_variables = {
    PROJECT_ID     = var.project_id
    image_families = "${local.namespaces-}gim-rhel-9,${local.namespaces-}gim-windows-2022"
  }
}

resource "google_cloud_scheduler_job" "delete_job" {
  name        = "${local.namespaces_}delete_job"
  description = "Job to run the delete_function after 1 year"
  schedule    = "0 9 * * *"
  time_zone   = "UTC"

  http_target {
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/${google_cloudfunctions_function.delete_function.name}"
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
    headers = {
      "Content-Type" = "application/json"
    }
  }
}

resource "google_cloudfunctions_function" "cleanup_function" {
  name    = "${local.namespaces_}cleanup_function"
  project = var.project_id
  region  = var.region
  runtime = "python39"
  timeout   = 520

  available_memory_mb          = 512
  source_archive_bucket        = google_storage_bucket.gcp_build.name
  source_archive_object        = google_storage_bucket_object.lifecycle.name
  trigger_http                 = true
  https_trigger_security_level = "SECURE_ALWAYS"
  entry_point                  = "main"
  service_account_email        = google_service_account.lifecycle_sa.email
  build_environment_variables = {
    GOOGLE_FUNCTION_SOURCE = "cleanup_vm.py"
  }
  environment_variables = {
    PROJECT_ID     = var.project_id
  }
}

resource "google_cloud_scheduler_job" "cleanup_job" {
  name        = "${local.namespaces_}cleanup_job"
  description = "Job to run the cleanup_function after 1 year"
  schedule    = "0 9 * * *"
  time_zone   = "UTC"

  http_target {
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/${google_cloudfunctions_function.cleanup_function.name}"
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
    headers = {
      "Content-Type" = "application/json"
    }
  }
}

#####################################################################################################

resource "google_service_account" "lifecycle_sa" {
  project      = var.project_id
  account_id   = "${local.namespace-}lifecycle-sa"
  display_name = "lifecycle_function Service Account"
}

resource "google_project_iam_member" "lifecycle_image_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.lifecycle_sa.email}"
}

resource "google_project_iam_member" "lifecycle_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.lifecycle_sa.email}"
}

