packer {
  required_plugins {
    google = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/google"
    }
  }
}

locals {
  gcp_image_tags = {
    "OSDistribution" = "${var.image_family}"
    "Contact"        = "HCC_CDTK@ds.uhc.com"
    "AppName"        = "CDTK Golden Images"
    "CostCenter"     = "44770-01508-USAMN022-160465"
    "ASKID"          = "AIDE_0077829"
    "SCM"            = "https://github.com/optum-eeps/hcc_lp_golden_image_bakery"
    "TaggingVersion" = "v1.0.1"
    "ImageType"      = "ApprovedOptumGoldenImage"
  }
  build_tags = merge({ "Name" = "${var.namespace-}builder-${var.image_family}" }, local.gcp_image_tags)
}

variable "namespace" {
  type    = string
  default = env("namespace")
}

variable "namespace-" {
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

variable "os_virtualization" {
  type    = string
  default = env("os_virtualization")
}

variable "os_mapping" {
  type    = string
  default = env("os_mapping")
}

variable "os_device" {
  type    = string
  default = env("os_device")
}

variable "os_root_volume" {
  type    = string
  default = env("os_root_volume")
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

variable "security_group" {
  type    = string
  default = env("security_group")
}

variable "instance_profile" {
  type    = string
  default = env("instance_profile")
}

variable "org_arns" {
  type    = string
  default = env("org_arns")
}

variable "date_created" {
  type    = string
  default = env("date_created")
}

variable "gcp_project" {
  type    = string
  default = env("gcp_project")
}

variable "gcp_image_regions" {
  type    = string
  default = env("gcp_image_regions")
}

locals {
  instance_type  = (var.os_arch=="arm64") ? "e2-small" : "e2-medium"
  use_proxy_flag = false
}

build {
  sources = [
    "source.google.compute_image.golden_gcp_image_build_specs"
  ]

  provisioner "file" {
    source = "certs"
    destination = "/tmp/"
  }
  
  provisioner "file" {
    sources = ["/tmp/UHG_Cloud_Linux_Server-snowagent-7.0.1-x64.deb","/tmp/UHG_Cloud_Linux_Server-snowagent-7.0.1-x64.rpm"]
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
      "--extra-vars", "image_regions=${join(",", jsondecode(var.gcp_image_regions))}",
      "--extra-vars", "os_type=${var.os_type}",
      "--extra-vars", "gcp_image_name=${var.namespace-}optum/${var.image_family}_${var.date_created}",
      "--extra-vars", "src_img_id=${build.SourceImage}",
      "--extra-vars", "src_img=${build.SourceImageName}",
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
      "taskkill /im sshd.exe /f",
      "fi"
    ] 
    environment_vars = [
      "image_family=${var.image_family}"
    ]
    pause_after       = "5m"
  }
}

source "google.compute_image" "golden_gcp_image_build_specs" {
  image_name             = "${var.namespace-}optum/${var.image_family}_${var.date_created}"
  image_description      = "HCC Golden Image for ${var.image_family}"
  project_id             = "${var.gcp_project}"
  source_image_family    = "${var.os_name}"
  source_image_project  = "${var.os_owner}"
  network               = "${var.network}"
  subnetwork            = "${var.subnet}"
  tags                  = local.gcp_image_tags
  boot_disk {
    initialize_params {
      image = "${var.os_mapping}"
      size  = 50
    }
  }
  labels                = local.build_tags
  machine_type          = local.instance_type
  metadata              = {
    "ssh-keys" = "${var.ssh_user}:${var.ssh_key}"
  }
  disk {
    auto_delete = true
    boot        = true
    size_gb     = 50
    type        = "pd-ssd"
  }
  encryption_key {
    kms_key_name = var.kms_key
  }
  zone                  = "us-central1-a"
  tags                  = local.gcp_image_tags
}
