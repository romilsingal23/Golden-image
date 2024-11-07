packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/googlecompute"
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
  build_tags = merge({ "Name" = "${var.namespace_dash}builder-${var.image_family}" }, local.image_tags)
}

variable "namespace" {
  type    = string
  default = env("namespace")
}

variable "namespace_dash" {
  type    = string
  default = env("namespacedash")
}

variable "image_family" {
  type    = string
  default = env("image_family")
}

variable "os_owner" {
  type    = string
  default = env("os_owner")
}

variable "os_name" {
  type    = string
  default = env("os_name")
}

variable "os_type" {
  type    = string
  default = env("os_type")
}

variable "os_arch" {
  type    = string
  default = env("os_arch")
}

variable "ssh_user" {
  type    = string
  default = env("ssh_user")
}

variable "network" {
  type    = string
  default = env("network")
}

variable "subnet" {
  type    = string
  default = env("subnet")
}

variable "kms_key" {
  type    = string
  default = env("kms_key")
}

variable "project_id" {
  type    = string
  default = env("project_id")
}

variable "date_created" {
  type    = string
  default = env("date_created")
}

locals {
  instance_type  = (var.os_arch == "arm64") ? "e2-medium" : "e2-small"
  use_proxy_flag = false
}

build {
  sources = [
    "source.googlecompute.golden_image_build_specs"
  ]

  provisioner "file" {
    source = "certs"
    destination = "/tmp/"
  }

  provisioner "file" {
    sources = ["/tmp/UHG_Cloud_Linux_Server-snowagent-7.0.1-x64.deb", "/tmp/UHG_Cloud_Linux_Server-snowagent-7.0.1-x64.rpm"]
    destination = "/tmp/"
  }

  provisioner "shell" {
    script            = "snowagent.sh"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
    execute_command   = "{{.Vars}} bash '{{.Path}}'"
  }

  provisioner "shell" {
    expect_disconnect = true
    script            = "update.sh"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
  }

  provisioner "shell" {
    expect_disconnect = true
    script            = "linux_certs_upload.sh"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
  }

  provisioner "ansible" {
    max_retries   = 3
    playbook_file = "./ansible/playbook.yml"
    user          = "${var.ssh_user}"
    use_proxy     = local.use_proxy_flag
    extra_arguments = [
      "--tags", "${var.image_family}",
      "--extra-vars", "csp=gcp",
      "--extra-vars", "architecture=${var.os_arch}",
      "--extra-vars", "instance_type=${local.instance_type}",
      "--extra-vars", "namespace=${var.namespace}",
      "--extra-vars", "image_family=${var.image_family}",
      "--extra-vars", "architecture=${var.os_arch}",
      "--extra-vars", "gcp_build_instance_id=${build.ID}",
      "--extra-vars", "os_type=${var.os_type}",
      "--extra-vars", "gcp_image_name=${var.namespace_dash}optum/${var.image_family}_${var.date_created}",
      "--extra-vars", "date_created=${var.date_created}"
    ]
  }

  provisioner "shell" {
    expect_disconnect = true
    script            = "gcp_cli.sh"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
  }

  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "if [[ $image_family != 'RHEL_9' && $image_family != 'ARM_RHEL_9' ]]; then",
      " echo rebooting ", 
      "sudo /sbin/reboot",
      "fi"
    ] 
    environment_vars = [
      "image_family=${var.image_family}"
    ]
    pause_after = "5m"
  }
}

source "googlecompute" "golden_image_build_specs" {
  project_id          = "${var.project_id}"
  source_image_family = "${var.os_name}"
  source_image_project = "${var.os_owner}"
  machine_type        = local.instance_type
  zone                = "us-central1-a"
  network             = "${var.network}"
  subnetwork          = "${var.subnet}"
  tags                = local.build_tags
  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  disk {
    image  = "${var.os_name}"
    type   = "pd-ssd"
    size   = 50
    labels = local.image_tags
    encrypt = true
    kms_key_name = "${var.kms_key}"
  }
  metadata = {
    ssh-keys = "packer:${var.ssh_user}"
  }
}
