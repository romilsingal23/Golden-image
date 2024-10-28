locals {
  gcp_build_name             = "gcp-build"
  namespaced_gcp_build_name  = "${local.namespace}-gcp-build"
  deploy_gcp_build           = merge(google_cloudfunctions_function.gcp_build.environment_variables, { "src_artifact" : data.archive_file.gcp_build_src.output_md5, "principal_id" : google_cloudfunctions_function.gcp_build.identity[0].principal_id })
  codebuild_image_name       = "BaseImage"
  build_resource_location    = local.is_local ? data.google_compute_region.build_network[0].location : google_compute_region.build_network[0].location
  build_resource_project_name = local.is_local ? data.google_project.build_network[0].name : google_project.build_network[0].name
  infra_name                 = "${local.namespace}_golden_image_gcp_build"
  subscription_with_underscores = replace(data.google_project.current.project_id, "-", "_")
  owner_group_name           = format("GCP_%s_Contributors", local.subscription_with_underscores)
}

data "archive_file" "gcp_build_src" {
  type        = "zip"
  source_dir  = "${path.module}/gcp-build"
  output_path = "${local.namespaced_gcp_build_name}.zip"
}

# Cloud Storage for Function App Infra

resource "google_storage_bucket" "gcp_build" {
  name                        = "${local.namespace}-gcpbuildfunc"
  location                    = "${local.build_resource_location}"
  force_destroy               = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "supported_images_blob" {
  name   = "supported-images.json"
  bucket = google_storage_bucket.gcp_build.name
  source = "${path.module}/../../supported_images.json"
}

resource "google_storage_bucket_object" "exceptional_images_blob" {
  name   = "exceptional-images.json"
  bucket = google_storage_bucket.gcp_build.name
  source = "${path.module}/../../exceptional-images.json"
}

resource "google_storage_bucket_object" "exceptional_images_access_blob" {
  name   = "exceptional-images-access.json"
  bucket = google_storage_bucket.gcp_build.name
  source = "${path.module}/exceptional_images_access.json"
}

data "archive_file" "ansible" {
  type        = "zip"
  source_dir  = "${path.module}/../../ansible"
  output_path = "${path.module}/codebuild/ansible.zip"
}

data "archive_file" "builder" {
  type        = "zip"
  source_dir  = "${path.module}/codebuild"
  output_path = "${path.root}/codebuild.zip"

  depends_on = [
    data.archive_file.ansible
  ]
}

resource "google_storage_bucket" "build" {
  name                        = "build-${random_id.bucket_suffix.hex}"
  location                    = "${local.build_resource_location}"
  force_destroy               = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "build_logs" {
  name                        = "gcp-build-logs-${random_id.bucket_suffix.hex}"
  location                    = "${local.build_resource_location}"
  force_destroy               = true
  uniform_bucket_level_access = true
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30
    }
  }
}

resource "google_cloudfunctions_function" "gcp_build" {
  name            = local.namespaced_gcp_build_name
  description     = "GCP build function for golden images"
  runtime         = "python39"
  available_memory_mb = 256
  source_archive_bucket = google_storage_bucket.gcp_build.name
  source_archive_object = google_storage_bucket_object.supported_images_blob.name
  entry_point     = "entry_point_function"

  environment_variables = {
    IS_LOCAL                    = local.is_local
    IS_POC                      = local.is_poc
    IS_PROD                     = local.is_prod
    DYNAMODB_TABLE_NAME         = data.google_secret_manager_secret_version.common_image_table.secret_data
    RESOURCE_PROJECT_NAME       = "${local.build_resource_project_name}"
    PROJECT_ID                  = data.google_project.current.project_id
    NAMESPACE                   = "${local.namespace}"
    STORAGE_BUCKET_NAME         = google_storage_bucket.gcp_build.name
    KEY_VAULT_SECRET            = "secret_key_vault_placeholder"
    GALLERY_NAME                = "${local.gallery_name}"
    EXCEPTION_GALLERY_NAME      = local.exceptional_gallery_name
    STORAGE_BUCKET              = google_storage_bucket.gcp_build.name
    GOOGLE_CLIENT_ID            = var.google_client_id
    GOOGLE_CLIENT_SECRET        = var.google_client_secret
    GOOGLE_TENANT               = var.google_tenant
    REGIONS                     = jsonencode(local.gcp_regions_list)
    MANAGED_IDENTITY            = google_service_account.managed_identity.email
    BUILD_IMAGE_NAME            = "${local.codebuild_image_name}"
    ASK_ID                      = "AIDE_0077829"
    INFRA_NAME                  = "${local.infra_name}"
    PROJECT_NAME                = "CDTK"
    EXCEPTION_STORAGE_ACCOUNT   = local.exceptional_storage_account_name
    SSH_PUBLIC_KEY              = "ssh_key_placeholder"
    TOPIC_NAME                  = google_pubsub_topic.images_notification_topic.name
    BACKUP_BUCKET_URL           = google_storage_bucket.gallery_backup.url
    EXCEPTION_BACKUP_BUCKET_URL = google_storage_bucket.exceptional_gallery_backup.url
  }

  event_trigger {
    event_type = "google.storage.object.finalize"
    resource   = google_storage_bucket.build.name
  }
}

# IAM Policies and Service Account

resource "google_service_account" "managed_identity" {
  account_id   = "managed-identity"
  display_name = "Managed Identity for GCP Build Function"
}

resource "google_project_iam_member" "storage_blob_contributor" {
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.managed_identity.email}"
}

resource "google_project_iam_member" "vm_instance_admin" {
  role   = "roles/compute.instanceAdmin"
  member = "serviceAccount:${google_service_account.managed_identity.email}"
}

resource "google_project_iam_member" "security_admin" {
  role   = "roles/securityAdmin"
  member = "serviceAccount:${google_service_account.managed_identity.email}"
}

# Cloud Build Trigger for Deployment

resource "google_cloud_build_trigger" "gcp_build" {
  name = "deploy-gcp-build"

  trigger_template {
    branch_name = "^main$"
    repo_name   = "gcp-cloud-platform"
  }

  build {
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "functions", "deploy", local.namespaced_gcp_build_name,
        "--source", google_storage_bucket.gcp_build.url,
        "--runtime", "python39",
        "--trigger-resource", google_storage_bucket.build.name,
        "--trigger-event", "google.storage.object.finalize",
        "--project", var.project_id
      ]
    }
  }
}
