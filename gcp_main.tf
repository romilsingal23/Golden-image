locals {
  gcp_build_name = "${local.namespaces-}golden-image-gcp-build"
}


# Cloud Storage for Function App Infra

resource "google_storage_bucket" "gcp_build" {
  name                        = "${local.namespaces-}gcp-build-bucket"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true

}

data "archive_file" "ansible" {
  type        = "zip"
  source_dir  = "${path.module}/../../ansible"
  output_path = "${path.module}/codebuild/ansible.zip"
}

resource "google_storage_bucket" "supported_images" {
  name                        = "${local.namespaces-}supported-images"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "supported_images" {
  bucket = google_storage_bucket.supported_images.name
  name   = "supported_images.json"
  source = "${path.module}/../../supported_images.json"
}

data "archive_file" "codebuild" {
  type        = "zip"
  source_dir  = "${path.module}/codebuild"
  output_path = "${path.module}/codebuild.zip"

  depends_on = [
    data.archive_file.ansible
  ]
}

resource "google_storage_bucket_object" "codebuild" {
  name   = "codebuild.zip"
  bucket = google_storage_bucket.gcp_build.name
  source = data.archive_file.codebuild.output_path
}

# Archive the Cloud Function Source Code
data "archive_file" "build_trigger" {
  type        = "zip"
  source_dir  = "${path.module}/build_trigger"
  output_path = "${path.module}/build_trigger.zip"
}

resource "google_storage_bucket_object" "build_trigger" {
  name   = "build_trigger_${uuid()}.zip"
  bucket = google_storage_bucket.gcp_build.name
  source = data.archive_file.build_trigger.output_path
}


data "aws_dynamodb_table" "common_image_table" {
  name = var.environment == "local" ? "smadu4-golden-images-metadata" : "${local.namespace-}golden-images-metadata"
}

data "aws_sns_topic" "images_notification_topic" {
  name = "smadu4-sns-notification-topic"
}

resource "google_cloudfunctions_function" "build_function" {
  name    = "${local.namespaces_}build_function"
  project = var.project_id
  region  = var.region
  runtime = "python39"

  available_memory_mb          = 128
  source_archive_bucket        = google_storage_bucket.gcp_build.name
  source_archive_object        = google_storage_bucket_object.build_trigger.name
  trigger_http                 = true
  https_trigger_security_level = "SECURE_ALWAYS"
  entry_point                  = "main"

  environment_variables = {
    PROJECT_ID              = var.project_id
    SUPPORTED_IMAGES_BUCKET = google_storage_bucket.supported_images.name
    CODEBUILD_BUCKET        = google_storage_bucket.gcp_build.name
    NETWORK                 = google_compute_network.gcp_build_network.name
    SUBNET                  = google_compute_subnetwork.gcp_build_subnet.name
    dynamodb_table          = data.aws_dynamodb_table.common_image_table.name
    path_to_console         = "https://us-east1.cloud.twistlock.com/us-1-111573393"
    prisma_base_url         = "us-east1.cloud.twistlock.com"
    aws_access_key          = "${local.namespaces-}access-key"
    aws_secret_key          = "${local.namespaces-}secret-key"
    service_account_id      = google_service_account.cloud_build.id
    prisma_username         = "prisma-username"
    prisma_password         = "prisma-password"
    namespace               = local.namespaces-
    kms_key                 = google_kms_crypto_key.crypto_key.id
    TOPIC_NAME              = data.aws_sns_topic.images_notification_topic.arn
  }
}

resource "google_cloud_scheduler_job" "build_trigger_job" {
  count       = var.environment == "local" ? 0 : 1
  name        = "${local.namespaces-}build-trigger-job"
  project     = var.project_id
  region      = var.region
  description = "Scheduled job to trigger Cloud Build on a cron schedule"
  schedule    = "0 5 * * *" # Cron expression #(every day at 5 AM UTC)
  time_zone   = "UTC"

  http_target {
    uri         = "https://${var.region}-${var.project_id}.cloudfunctions.net/${google_cloudfunctions_function.build_function.name}"
    http_method = "POST"
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
    headers = {
      "Content-type" = "application/json"
    }
  }
}

resource "google_kms_key_ring" "key_ring" {
  name     = "${local.namespaces-}key-ring"
  location = "us"
}

resource "google_kms_crypto_key" "crypto_key" {
  name     = "${local.namespaces_}key"
  key_ring = google_kms_key_ring.key_ring.id
  purpose  = "ENCRYPT_DECRYPT"
}

resource "google_kms_crypto_key_iam_member" "kms_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.crypto_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${var.project_number}@compute-system.iam.gserviceaccount.com"
}

resource "null_resource" "delete_artifacts" {
  provisioner "local-exec" {
    command = "bash ${path.module}/delete_artifacts.sh ${var.project_id}"
  }

  triggers = {
    timestamp = timestamp() # Ensure it runs every time
  }
  depends_on = [google_cloudfunctions2_function.adoption_function, google_cloudfunctions_function.build_function, google_cloudfunctions_function.delete_function, google_cloudfunctions_function.obsolete_function, google_cloudfunctions_function.cleanup_function]
}
