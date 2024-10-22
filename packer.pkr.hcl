# Packer template in HCL format using RHEL 9
variable "project_id" {
  type    = string
  default = "consumer-project-431315"
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "zone" {
  type    = string
  default = "us-east1-b"
}

variable "vpc_name" {
  type    = string
  default = "myvpc1"
}

variable "subnet_name" {
  type    = string
  default = "subnet2"
}

source "googlecompute" "golden_image" {
  project_id          = var.project_id
  source_image_family = "rhel-9"
  zone                = var.zone
  ssh_username        = "packer"
  machine_type        = "n1-standard-1"
  subnetwork          = var.subnet_name
  network             = var.vpc_name
  use_internal_ip     = true
  image_name          = "golden-image-${formatdate("YYYYMMDDHHMM", timestamp())}"
  image_family        = "golden-family"
}

build {
  sources = ["source.googlecompute.golden_image"]

  provisioner "ansible" {
    playbook_file = "./playbook.yml"
  }

  provisioner "shell" {
    inline = [
      "gcloud secrets versions access latest --secret='certificate-secret' > /etc/ssl/certs/cert.pem",
      "gcloud secrets versions access latest --secret='private-key-secret' > /etc/ssl/private/key.pem"
    ]
  }
}
