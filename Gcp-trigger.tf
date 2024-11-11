locals {
  gcp_build_name            = "gcp-build"
  namespaced_gcp_build_name = "${local.namespace}-gcp-build"
  codebuild_image_name      = "BaseImage"
  namespace                 = "dev"

}

# Cloud Storage for Function App Infra

resource "google_storage_bucket" "gcp_build" {
  name                        = "gcp-build1"
  location                    = var.region
  project                     = var.project_id
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

data "archive_file" "ansible" {
  type        = "zip"
  source_dir  = "${path.module}/../../ansible"
  output_path = "${path.module}/codebuild/ansible.zip"
}

resource "google_storage_bucket" "supported_images" {
  name                        = "${local.namespace}-supported-images"
  location                    = var.region
  project                     = var.project_id
  force_destroy               = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "supported_images" {
  bucket = google_storage_bucket.supported_images.name
  name   = "supported_images.json"
  source = "${path.module}/../../supported_images.json"
}

resource "google_storage_bucket_object" "exceptional_images" {
  name   = "exceptional-images.json"
  bucket = google_storage_bucket.gcp_build.name
  source = "${path.module}/../../exceptional-images.json"
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
  name   = "build_trigger.zip"
  bucket = google_storage_bucket.gcp_build.name
  source = data.archive_file.build_trigger.output_path
}

resource "google_cloudfunctions2_function" "gcp_build" {
  name        = local.namespaced_gcp_build_name
  description = "GCP build function for golden images"
  #available_memory_mb   = 256
  project  = var.project_id
  location = var.region
  build_config {
    entry_point = "main"
    runtime     = "python312"

    source {
      storage_source {
        bucket = google_storage_bucket.gcp_build.name
        object = google_storage_bucket_object.build_trigger.name
      }
    }

    environment_variables = {
      GOOGLE_FUNCTION_SOURCE = "main.py"
      #PROJECT_NAME           = "hcc-gcp-goldenimages-poc"
      PROJECT_ID              = var.project_id
      SUPPORTED_IMAGES_BUCKET = google_storage_bucket.supported_images.name
      NAMESPACE               = local.namespace
      NETWORK                 = google_compute_network.vpc1.id
      SUBNET                  = google_compute_subnetwork.subnetwork1.id
      #namespacedash  = "my-namespace-dash"
      #IMAGE_FAMILY   = "WILL_BE_OVERWRITTEN"
      #OS_OWNER       = "WILL_BE_OVERWRITTEN"
      #OS_NAME        = "WILL_BE_OVERWRITTEN"
      #OS_TYPE        = "WILL_BE_OVERWRITTEN"
      #OS_ARCH        = "WILL_BE_OVERWRITTEN"
      #SSH_USER       = "WILL_BE_OVERWRITTEN"
      #kms_key        = "projects/my-project-id/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key"
      #DATE_CREATED   = "WILL_BE_OVERWRITTEN"      
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 120
  }

  /*
  event_trigger {
    event_type = "google.storage.object.finalize"
  }
  */
}

# Cloud Build Trigger for Deployment

# Load the template file (images.json)
data "template_file" "substitutions" {
  template = file("../../supported_images.json")
}

# Parse the JSON into a local map
locals {
  images_data = jsondecode(data.template_file.substitutions.rendered)

  # Extract GCP-specific data for all OS types (RHEL_8, RHEL_9, Windows_22, etc.)
  gcp_images = local.images_data["gcp"]
}

# Cloud Build Trigger for each OS type
resource "google_cloudbuild_trigger" "image_build_trigger" {
  for_each = local.gcp_images

  project     = var.project_id
  name        = "image-build-trigger-${each.key}"
  description = "Trigger to build the ${each.key} image with dynamic substitution variables"
  trigger_template {
    branch_name = "main"
    repo_name   = "your-repo-name"
  }

  substitutions = {
    "_IMAGE_NAME"          = each.value["image_name"]
    "_SOURCE_IMAGE_FAMILY" = each.value["source_image_family"]
    "_IMAGE_PROJECT"       = each.value["image_project"]
    "_ARCHITECTURE"        = each.value["architecture"]
    "_DEVICE_TYPE"         = each.value["device_type"]
    "_ROOT_VOLUME"         = each.value["root_volume"]
    "_SSH_USER"            = each.value["ssh_username"]
  }

  filename = "codebuild/cloudbuild.yaml"
}

/*
resource "google_cloud_scheduler_job" "scheduled_trigger_job" {
  for_each = local.gcp_images
  name        = "scheduled-trigger-job"
  description = "Scheduled job to trigger Cloud Build on a cron schedule"
  schedule    = "0 0 * * *" # Cron expression (e.g., every day at midnight)
  time_zone   = "UTC"

  http_target {
    uri = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/triggers/${google_cloudbuild_trigger.image_build_trigger.id}:run"
    http_method = "POST"
    
    headers = {
      "Content-type" = "application/json"
    }
    
  }
}
*/
/*
resource "local_file" "cloudbuild" {
  content = yamlencode({
    version = "0.2"
    steps = {
      install = {
        commands = [
          "curl -qL -o packer.zip https://releases.hashicorp.com/packer/1.8.2/packer_1.8.2_linux_amd64.zip && unzip packer.zip",
          "./packer version",
          "curl -qL -o terraform.zip https://releases.hashicorp.com/terraform/1.2.3/terraform_1.2.3_linux_amd64.zip && unzip terraform.zip && mv terraform /usr/bin",
          "terraform version",
          "pip install loguru pywinrm pyyaml ansible==2.10 requests aws_requests_auth azure.identity azure.storage.blob",
          "ansible --version",
          "curl https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb -o session-manager-plugin.deb",
          "sudo dpkg -i session-manager-plugin.deb",
          "session-manager-plugin",
        ]
      }
      build = {
        commands = [
          "./workspace/execute_packer.sh"
        ]
      }
    }
  })
  filename = "${path.module}/codebuild/cloudbuild.yml"
}
*/
resource "google_storage_bucket" "build_logs" {
  name          = "gcp-build-logs"
  location      = var.region
  force_destroy = true
  project       = var.project_id

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

resource "google_secret_manager_secret" "secret1" {
  project   = var.project_id
  secret_id = "secret1"
  replication {
    user_managed {
      replicas {
        location = "us-east1"
      }
    }
  }
}

# IAM Policies and Service Account

resource "google_service_account" "managed_identity" {
  account_id   = "managed-identity"
  display_name = "Managed Identity for GCP Build Function"
  project      = var.project_id
}

resource "google_project_iam_member" "storage_contributor" {
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.managed_identity.email}"
  project = var.project_id
}

resource "google_project_iam_member" "vm_instance_admin" {
  role    = "roles/compute.instanceAdmin"
  member  = "serviceAccount:${google_service_account.managed_identity.email}"
  project = var.project_id
}

/*
resource "google_project_iam_member" "security_admin" {
  role   = "roles/securityAdmin"
  member = "serviceAccount:${google_service_account.managed_identity.email}"
  project  = var.project_id
}
*/
