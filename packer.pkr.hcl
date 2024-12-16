packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/googlecompute"
    }

    ansible = {
      version = "~> 1"
      source = "github.com/hashicorp/ansible"
    }

  }
}

locals {
  image_tags = {
    "OSDistribution" = "${var.image_family}"
    "Contact"        = "HCC_CDTK@ds.uhc.com"
    "AppName"        = "CDTK Golden Images"
    "CostCenter"     = "44770-01508-USAMN022-160465"
    "ASKID"          = "AIDE_0077829"
    "SCM"            = "https://github.com/optum-eeps/hcc_lp_golden_image_bakery"
    "TaggingVersion" = "v1.0.1"
    "ImageType"      = "ApprovedOptumGoldenImage"
  }
}

variable "source_image_family" {
  type    = string
  default = env("SOURCE_IMAGE_FAMILY")
}
variable "namespace" {
  type    = string
  default = env("namespace")
}
variable "image_family" {
  type    = string
  default = env("IMAGE_FAMILY")
}

variable "os_owner" {
  type    = string
  default = env("os_owner")
}

variable "os_name" {
  type    = string
  default = env("OS_NAME")
}

variable "os_type" {
  type    = string
  default = env("OS_TYPE")
}

variable "os_arch" {
  type    = string
  default = env("OS_ARCH")
}

variable "ssh_username" {
  type    = string
  default = env("SSH_USERNAME")
}

variable "network" {
  type    = string
  default = env("NETWORK")
}


variable "gim_family" {
  type    = string
  default = env("GIM_FAMILY")
}

variable "subnet" {
  type    = string
  default = env("SUBNET")
}

variable "project_id" {
  type    = string
  default = env("PROJECT_ID")
}

variable "date_created" {
  type    = string
  default = env("DATE_CREATED")
}

variable "kms_key" {
  type    = string
  default = env("kms_key")
}

locals {
  instance_type  = (var.os_arch == "arm64") ? "e2-medium" : "e2-small"
  use_proxy_flag = false
}

build {
  sources = ["source.googlecompute.golden_image_build_specs"]

  provisioner "file" {
    source = "certs"
    destination = "/tmp/"
  }

  provisioner "shell" {
    expect_disconnect = true
    script            = "linux_certs_upload.sh"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
  }

  provisioner "file" {
    sources = ["/tmp/UHG_Cloud_Linux_Server-snowagent-7.0.1-x64.rpm"]
    destination = "/tmp/"
  }

  provisioner "shell" {
    script            = "snowagent.sh"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
    execute_command   = "{{.Vars}} bash '{{.Path}}'"
  }

  provisioner "ansible" {
    max_retries   = 3
    playbook_file = "./ansible/playbook.yml"
    user          = "${var.ssh_username}"
    use_proxy           = local.use_proxy_flag
    extra_arguments = [
      "--tags", "${var.image_family}",
      "--extra-vars", "csp=gcp",
      "--extra-vars", "architecture=${var.os_arch}",
      "--extra-vars", "instance_type=${local.instance_type}",
      "--extra-vars", "image_family=${var.image_family}",
      "--extra-vars", "namespace=${var.namespace}",
      "--extra-vars", "os_type=${var.os_type}",
      "--extra-vars", "image_name=${var.namespace}${var.gim_family}-${var.date_created}",
      "--extra-vars", "date_created=${var.date_created}"
    ]
  }

  provisioner "shell" {
    expect_disconnect = true
    script            = "update.sh"
  }

}

source "googlecompute" "golden_image_build_specs" {
  project_id          = var.project_id
  source_image_family = var.source_image_family # It always returns its latest image that is not deprecated
  image_name          = "${var.namespace}${var.gim_family}-${var.date_created}"
  image_family        = var.gim_family
  image_labels        = {image_type: "golden-image"}
  machine_type        = local.instance_type
  omit_external_ip    = true
  use_internal_ip     = true
  use_iap      = true
  zone                = "us-east1-b"
  network             = var.network
  subnetwork          = var.subnet
  ssh_username        = var.ssh_username
  tags               = ["packer-build"]
  image_encryption_key {
    kmsKeyName = var.kms_key
  }
  metadata = {
    ssh-keys = "packer:${var.ssh_username}"
  }
}
