
packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  ami_tags = {
    "OSDistribution" = "${var.image_family}"
    #"SourceImage"    = "${build.SourceAMI}"
    "Contact"        = "HCC_CDTK@ds.uhc.com"
    "AppName"        = "CDTK Golden Images"
    "CostCenter"     = "44770-01508-USAMN022-160465"
    "ASKID"          = "AIDE_0077829"
    "SCM"            = "https://github.com/optum-eeps/hcc_lp_golden_image_bakery"
    "TaggingVersion" = "v1.0.1"
    "ImageType"      = "ApprovedOptumGoldenImage"
  }
  build_tags = merge({ "Name" = "${var.namespace-}builder-${var.image_family}" }, local.ami_tags)
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

variable "vpc_id" {
  type    = string
  default = env("vpc_id")
}

variable "subnet_id" {
  type    = string
  default = env("subnet_id")
}

variable "kms_id" {
  type    = string
  default = env("kms_id")
}

variable "security_group_id" {
  type    = string
  default = env("security_group_id")
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

variable "kms_alias_map" {
  type    = map(string)
  default = {}
}

variable "ami_regions" {
  type    = string
  default = env("ami_regions")
}

variable "instance_type_x86_64" {
  type    = string
  default = "t3.large"
}

variable "instance_type_arm64" {
  type    = string
  default = "t4g.large"
}

locals {
  instance_type  = (var.os_arch=="arm64") ? var.instance_type_arm64 : var.instance_type_x86_64
  use_proxy_flag = false
}

build {
  sources = [
    "source.amazon-ebs.golden_ami_build_specs"
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

  # Ansible can't run on RHEL without installing python first; it does not come preinstalled
  # Also need to remove the base kernel from RHEL since it is vulnereable and updating doesn't remove it
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
      "--extra-vars", "csp=aws",
      "--extra-vars", "architecture=${var.os_arch}",
      "--extra-vars", "instance_type=${local.instance_type}",
      "--extra-vars", "namespace=${var.namespace}",
      "--extra-vars", "image_family=${var.image_family}",
      "--extra-vars", "architecture=${var.os_arch}",
      "--extra-vars", "aws_build_instance_id=${build.ID}",
      "--extra-vars", "ami_regions=${join(",", jsondecode(var.ami_regions))}",
      "--extra-vars", "os_type=${var.os_type}",
      "--extra-vars", "ami_name=${var.namespace-}optum/${var.image_family}_${var.date_created}",
      "--extra-vars", "src_img_id=${build.SourceAMI}",
      "--extra-vars", "src_img=${build.SourceAMIName}",
      "--extra-vars", "date_created=${var.date_created}"
    ]
  }
  provisioner "shell" {
    expect_disconnect = true
    script            = "aws_cli.sh"
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


source "amazon-ebs" "golden_ami_build_specs" {
  ami_name             = "${var.namespace-}optum/${var.image_family}_${var.date_created}"
  ami_description      = "HCC Golden AMI for ${var.image_family}"
  region               = "us-east-1"
  instance_type        = local.instance_type
  sriov_support        = true
  ena_support          = true
  communicator         = "ssh"
  ssh_interface        = "session_manager"
  user_data_file       = "ssmagent_install_rhel.sh"
  ssh_username         = "${var.ssh_user}"
  vpc_id               = "${var.vpc_id}"
  subnet_id            = "${var.subnet_id}"
  security_group_ids   = ["${var.security_group_id}"]
  iam_instance_profile = "${var.instance_profile}"
  ami_regions          = jsondecode(var.ami_regions)
  ami_org_arns         = jsondecode(var.org_arns)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  launch_block_device_mappings {
    device_name = "${var.os_root_volume}"
    encrypted   = true
    kms_key_id  = "${var.kms_id}"
    delete_on_termination = true
  }
  encrypt_boot       = true
  region_kms_key_ids = var.kms_alias_map
  run_tags           = local.build_tags
  tags               = local.ami_tags
  source_ami_filter {
    filters = {
      "name"                             = "${var.os_name}"
      "virtualization-type"              = "${var.os_virtualization}"
      "root-device-type"                 = "${var.os_device}"
      "architecture"                     = "${var.os_arch}"
      "block-device-mapping.volume-type" = "${var.os_mapping}"
    }
    owners      = ["${var.os_owner}"]
    most_recent = true
  }
}

