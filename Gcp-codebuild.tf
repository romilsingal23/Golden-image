provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  build_name          = "gcp-image-builder"
  namespace           = var.namespace
  namespace_dash      = replace(var.namespace, "_", "-")
  shared_org_arn_list = ["org1", "org2"]
  ami_regions_list    = ["us-central1", "europe-west1"]
  client_secret       = var.client_secret
  tenant_id           = var.tenant_id
  client_id           = var.client_id
  storage_account_url = var.storage_account_url
}

# GCP Storage Bucket
resource "google_storage_bucket" "builder" {
  name          = "${local.build_name}-${random_id.bucket_suffix.hex}"
  location      = var.region
  force_destroy = true
}

# Encryption on Storage Bucket
resource "google_storage_bucket_iam_member" "deny_insecure_access" {
  bucket   = google_storage_bucket.builder.name
  role     = "roles/storage.objectViewer"
  member   = "allUsers"
  condition {
    title       = "DenyInsecureCommunications"
    expression  = "request.auth != null && request.url.scheme == 'https'"
    description = "Only allow secure (HTTPS) access"
  }
}

# Random ID for unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# IAM Role for Builder
resource "google_service_account" "builder" {
  account_id   = "${local.build_name}_account"
  display_name = "GCP Image Builder Account"
}

# IAM Role Policy Binding for Bucket Access
resource "google_storage_bucket_iam_member" "builder_access" {
  bucket = google_storage_bucket.builder.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.builder.email}"
}

# Custom IAM Role with necessary permissions
resource "google_project_iam_custom_role" "builder_role" {
  role_id     = "GCPImageBuilderRole"
  title       = "GCP Image Builder Role"
  description = "Custom role for image building"
  permissions = [
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.start",
    "compute.instances.stop",
    "compute.instances.get",
    "compute.instances.list",
    "compute.images.create",
    "compute.images.delete",
    "compute.images.get",
    "storage.buckets.get",
    "storage.objects.create",
    "storage.objects.get",
    "storage.objects.delete",
    "cloudkms.cryptoKeyVersions.useToEncrypt",
    "cloudkms.cryptoKeyVersions.useToDecrypt",
    "cloudkms.cryptoKeys.get",
    "cloudkms.cryptoKeys.list",
    "bigtable.instances.get",
    "bigtable.tables.get",
    "bigtable.tables.readRows",
  ]
}

# Bind the custom role to the service account
resource "google_project_iam_member" "builder_role_binding" {
  project = var.project_id
  role    = google_project_iam_custom_role.builder_role.id
  member  = "serviceAccount:${google_service_account.builder.email}"
}

# Secrets Manager for storing sensitive data
resource "google_secret_manager_secret" "image_api_url" {
  secret_id = "${local.namespace_dash}_image_api_url"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "image_api_url_version" {
  secret      = google_secret_manager_secret.image_api_url.id
  secret_data = var.image_api_url
}

# GCP Cloud Build for the Image Builder Project
resource "google_cloudbuild_trigger" "builder" {
  name = local.build_name

  substitutions = {
    _NAMESPACE              = local.namespace
    _NAMESPACEDASH          = local.namespace_dash
    _ORG_ARNS               = jsonencode(local.shared_org_arn_list)
    _AMI_REGIONS            = jsonencode(local.ami_regions_list)
    _VPC_ID                 = google_compute_network.build_network.id
    _SUBNET_ID              = google_compute_subnetwork.build_network_public.id
    _EKS_SUBNET_1           = google_compute_subnetwork.build_network_private.id
    _EKS_SUBNET_2           = google_compute_subnetwork.build_network_private_2.id
    _IMAGE_API_ENDPOINT     = google_secret_manager_secret.image_api_url.id
    _BUCKET_NAME            = google_storage_bucket.builder.name
    _KMS_KEY_ID             = google_kms_crypto_key.my_key.self_link
    _KMS_ALIAS_MAP          = local.kms_alias_map
    _SECURITY_GROUP_ID      = google_compute_firewall.build_instance_sg.id
    _EMR_SERVICE_SG_ID      = google_compute_firewall.service_access.id
    _EMR_MASTER_SG_ID       = google_compute_firewall.master.id
    _EMR_KMS_KEY            = google_kms_crypto_key.emr_scan_notification.self_link
    _INSTANCE_PROFILE       = google_service_account.builder.email
    _IMAGE_TABLE            = google_bigtable_instance.common_image_table.instance_id
    _OS_TYPE                = "WILL_BE_OVERWRITTEN"
    _IMAGE_FAMILY           = "WILL_BE_OVERWRITTEN"
    _OS_OWNER               = "WILL_BE_OVERWRITTEN"
    _OS_NAME                = "WILL_BE_OVERWRITTEN"
    _OS_ARCH                = "WILL_BE_OVERWRITTEN"
    _OS_VIRTUALIZATION      = "WILL_BE_OVERWRITTEN"
    _OS_MAPPING             = "WILL_BE_OVERWRITTEN"
    _OS_DEVICE              = "WILL_BE_OVERWRITTEN"
    _OS_ROOT_VOLUME         = "WILL_BE_OVERWRITTEN"
    _SSH_USER               = "WILL_BE_OVERWRITTEN"
    _DATE_CREATED           = "WILL_BE_OVERWRITTEN"
    _CLIENT_SECRET          = local.client_secret
    _TENANT_ID              = local.tenant_id
    _CLIENT_ID              = local.client_id
    _STORAGE_ACCOUNT_URL    = local.storage_account_url
  }

  # Cloud Build steps
  build {
    step {
      name = "gcr.io/cloud-builders/curl"
      args = [
        "-o", "packer.zip", "https://releases.hashicorp.com/packer/1.8.2/packer_1.8.2_linux_amd64.zip"
      ]
    }
    step {
      name = "gcr.io/cloud-builders/unzip"
      args = ["packer.zip"]
    }
    step {
      name = "gcr.io/cloud-builders/curl"
      args = [
        "-o", "terraform.zip", "https://releases.hashicorp.com/terraform/1.2.3/terraform_1.2.3_linux_amd64.zip"
      ]
    }
    step {
      name = "gcr.io/cloud-builders/unzip"
      args = ["terraform.zip"]
    }
    step {
      name = "gcr.io/cloud-builders/pip"
      args = [
        "install", "loguru", "pywinrm", "pyyaml", "ansible==2.10", "requests", 
        "aws_requests_auth", "azure.identity", "azure.storage.blob"
      ]
    }
    step {
      name = "gcr.io/cloud-builders/execute"
      args = ["./execute_packer.sh"]
    }
  }
}

# Additional resources like networking, firewalls, and KMS key
resource "google_compute_network" "build_network" {
  name = "build-network"
}

resource "google_compute_subnetwork" "build_network_public" {
  name          = "build-network-public"
  network       = google_compute_network.build_network.id
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
}

resource "google_compute_subnetwork" "build_network_private" {
  name          = "build-network-private"
  network       = google_compute_network.build_network.id
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
}

resource "google_compute_subnetwork" "build_network_private_2" {
  name          = "build-network-private-2"
  network       = google_compute_network.build_network.id
  ip_cidr_range = "10.0.3.0/24"
  region        = var.region
}

resource "google_compute_firewall" "build_instance_sg" {
  name    = "build-instance-sg"
  network = google_compute_network.build_network.id

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }
}

resource "google_kms_key_ring" "image_key_ring" {
  name     = "image-key-ring"
  location = var.region
}

resource "google_kms_crypto_key" "my_key" {
  name            = "my-key"
  key_ring        = google_kms_key_ring.image_key_ring.id
  rotation_period = "100000s"
}

# Sample Bigtable Instance for storing image data
resource "google_bigtable_instance" "common_image_table" {
  name         = "common-image-table"
  cluster {
    cluster_id   = "common-image-cluster"
    zone         = "${var.region}-a"
    num_nodes    = 3
    storage_type = "HDD"
  }
}
