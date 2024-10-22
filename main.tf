provider "google" {
  project = var.project_id
  region  = var.region
}

# Create VPC Network
resource "google_compute_network" "myvpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

# Create Subnet
resource "google_compute_subnetwork" "my_subnet" {
  name          = var.subnet_name
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.myvpc.id
}

# Create Service Account for Golden VM
resource "google_service_account" "golden_vm_service_account" {
  account_id   = var.service_account_name
  display_name = "Service Account for Golden VM"
}

# Grant Secret Manager Access Role
resource "google_project_iam_member" "secret_manager_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.golden_vm_service_account.email}"
}

# Grant Compute Admin Role
resource "google_project_iam_member" "compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.golden_vm_service_account.email}"
}

# Create Cloud Storage Bucket for Cloud Function
resource "google_storage_bucket" "cloud_function_bucket" {
  name     = var.cloud_function_bucket
  location = var.region
}

# Create Cloud Function for Image Lifecycle Management
resource "google_cloudfunctions_function" "lifecycle_handler" {
  name        = var.cloud_function_name
  description = "Handles lifecycle management for images"
  runtime     = "python39"  # Adjust as needed
  entry_point = "handler"    # Name of the function in your Python script
  source_archive_bucket = google_storage_bucket.cloud_function_bucket.name
  source_archive_object = "lifecycle_handler.py.zip"  # Zip file containing your Python code
  trigger_http = true

  available_memory_mb = 256
  timeout = 60

  labels = var.labels
}

# Create Cloud Build Trigger
resource "google_cloud_build_trigger" "trigger" {
  project = var.project_id
  trigger_template {
    branch_name = "main"  # Adjust based on your branch name
    repo_name   = "your-repo-name"  # Replace with your actual repo name
  }

  build {
    steps {
      name = "gcr.io/cloud-builders/terraform"
      args = ["apply", "-auto-approve"]
    }
    images = ["gcr.io/${var.project_id}/your-image-name"]  # Specify your image name
  }
}

# Create Golden VM Instance
resource "google_compute_instance" "golden_vm" {
  name         = "golden-vm"
  machine_type = "n1-standard-1"
  zone         = "${var.region}-b"  # Adjust the zone as needed

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"  # Use a public image or your custom image
    }
  }

  network_interface {
    network    = google_compute_network.myvpc.name
    subnetwork = google_compute_subnetwork.my_subnet.name

    access_config {
      // This is for external IP; remove if you want a private IP only
    }
  }

  tags = var.tags

  service_account {
    email  = google_service_account.golden_vm_service_account.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

# Create Cloud NAT to allow the Golden VM to connect to external services
resource "google_compute_router" "nat_router" {
  name    = "nat-router"
  region  = var.region
  network = google_compute_network.myvpc.id
}

resource "google_compute_router_nat" "nat_gateway" {
  name   = "nat-gateway"
  region = var.region
  router = google_compute_router.nat_router.name

  nat_ip_allocate_option = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = ["ALL_SUBNETWORKS_ALL_IP_RANGES"]
}

# Cleanup Old VMs and Disks
resource "null_resource" "cleanup_old_resources" {
  provisioner "local-exec" {
    command = <<EOT
      gcloud compute instances list --filter="name:old-vm-name" --format="value(name)" | xargs -I {} gcloud compute instances delete {} --zone=${var.region}-b --quiet
      gcloud compute disks list --filter="name:old-disk-name" --format="value(name)" | xargs -I {} gcloud compute disks delete {} --zone=${var.region}-b --quiet
    EOT
  }
}
