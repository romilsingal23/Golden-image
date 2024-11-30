provider "google" {
  project = "YOUR_PROJECT_ID"  # Replace with your project ID
  region  = "us-central1"       # Cloud Function region
}

resource "google_storage_bucket" "bucket" {
  name     = "rsingal-gcp-build-bucket"  # Replace with your GCS bucket name
  location = "US"
}

resource "google_cloudfunctions2_function" "vm_image_labels_function" {
  name        = "export-vm-image-labels"
  description = "Cloud Function to export VM image labels"

  region      = "us-central1"
  runtime     = "python310"   # Specify runtime as Python 3.10
  entry_point = "export_vm_image_labels"

  build_config {
    entry_point = "export_vm_image_labels"
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = "vm_image_labels_code.zip"  # Replace with the location of the ZIP file
      }
    }
  }

  service_account_email = "YOUR_SERVICE_ACCOUNT@YOUR_PROJECT_ID.iam.gserviceaccount.com"  # Replace with your service account

  environment_variables = {
    BUCKET_NAME = "rsingal-gcp-build-bucket"
  }
}

resource "google_storage_bucket_object" "function_code" {
  name   = "vm_image_labels_code.zip"
  bucket = google_storage_bucket.bucket.name
  source = "vm_image_labels_code.zip"  # Path to your zip file containing your Cloud Function code
}

resource "google_cloud_scheduler_job" "weekly_job" {
  name        = "weekly-export-vm-image-labels"
  description = "Job to run the export_vm_image_labels function weekly"
  schedule    = "0 9 * * 1"  # Cron for weekly, every Monday at 9:00 AM
  time_zone   = "America/Los_Angeles"

  http_target {
    uri        = google_cloudfunctions2_function.vm_image_labels_function.https_trigger_url
    http_method = "POST"
    headers = {
      "Content-Type" = "application/json"
    }
  }

  # Allow Cloud Scheduler to invoke the function
  iam_member {
    role   = "roles/cloudfunctions.invoker"
    member = "serviceAccount:${google_cloud_scheduler_job.weekly_job.service_account_email}"
  }
}

resource "google_project_iam_member" "cloud_scheduler_invoker" {
  project = "YOUR_PROJECT_ID"  # Replace with your project ID
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_cloud_scheduler_job.weekly_job.service_account_email}"
}
