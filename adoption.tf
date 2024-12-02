data "archive_file" "adoption" {
  type        = "zip"
  source_dir  = "${path.module}/adoption"
  output_path = "${path.module}/adoption.zip"
}

resource "google_storage_bucket_object" "adoption" {
  name           = "adoption.zip"
  bucket         = google_storage_bucket.gcp_build.name
  source         = data.archive_file.adoption.output_path
  detect_md5hash = filebase64sha256(data.archive_file.adoption.output_path)
}


resource "google_cloudfunctions2_function" "adoption_function" {
  name        = "${local.namespace_}adoption_report"
  description = "Cloud Function to export VM image labels"

  location = "us-east1"

  build_config {
    entry_point = "export_vm_image_labels"
    runtime     = "python310"
    source {
      storage_source {
        bucket = google_storage_bucket.gcp_build.name
        object = google_storage_bucket_object.adoption.name
      }
    }
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.gcp_build.name
      PROJECT_ID  = var.project_id
    }

  }
  service_config {
    max_instance_count  = 3
    min_instance_count = 1
    available_memory    = "4Gi"
    timeout_seconds     = 60
    max_instance_request_concurrency = 80
    available_cpu = "4"
    #service_account_email        = google_service_account.adoption_sa.email
 
  }

}

resource "google_cloud_scheduler_job" "adoption_job" {
  name        = "weekly-export-vm-image-labels"
  description = "Job to run the export_vm_image_labels function weekly"
  schedule    = "0 9 * * 1" # Cron for weekly, every Monday at 9:00 AM
  time_zone   = "UTC"

  http_target {
    uri         = google_cloudfunctions2_function.adoption_function.service_config[0].uri
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
    headers = {
      "Content-Type" = "application/json"
    }
  }
}
