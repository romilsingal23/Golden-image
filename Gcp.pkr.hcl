source "googlecompute" "golden_image_build_specs" {
  project_id      = var.project_id
  image_name      = "${var.namespace}-${var.image_family}-${timestamp()}"
  image_family    = var.image_family
  image_description = "HCC Golden Image for ${var.image_family}"
  zone            = "us-central1-a" # Adjust to your preferred zone
  machine_type    = var.instance_type
  network         = var.vpc_network # Custom VPC
  subnetwork      = var.subnet # Custom subnet
  use_internal_ip = true
  tags            = var.build_tags

  # Service account to access required resources
  service_account_email = var.service_account_email
  scopes                = ["https://www.googleapis.com/auth/cloud-platform"]

  # Disk configuration
  disk_size            = var.disk_size # Customize based on your requirements
  disk_type            = "pd-ssd" # SSD for performance
  image_encryption_key {
    kms_key_name       = var.kms_key_name # Set your KMS key
  }

  # Metadata options
  metadata = {
    enable-oslogin             = "TRUE"
    block-project-ssh-keys     = "TRUE"
  }

  # Additional tags or labels for organizing resources
  labels = {
    environment                = "golden-image"
    department                 = var.department
  }
}

build {
  sources = ["source.googlecompute.golden_image_build_specs"]

  provisioner "shell" {
    script = "./execute_packer.sh" # The custom setup script
  }
              }
