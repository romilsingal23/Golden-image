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
  default = "us-east1-c"
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
  image_name          = "golden-image-${formatdate("YYYYMMDDHHMM", timestamp())}"
  image_family        = "golden-family"
  #use_internal_ip    = true
  #omit_external_ip   = true
  #use_iap            = true
  #use_os_login       = true
  #metadata = {
  #  block-project-ssh-keys = "true"
  #}
  tags = ["allow-ssh"]

}

build {
  sources = ["source.googlecompute.golden_image"]

  provisioner "shell" {
   inline = [
    "sudo yum -y update",
    "sudo dnf -y install ansible-core"
   ]
 }

  provisioner "ansible-local" {
    playbook_file = "./playbook.yml"
  }

}
