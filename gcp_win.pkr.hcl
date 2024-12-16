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
  rand_src = uuidv4()
  gcp_labels = {
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

variable "image_family" {
  type    = string
  default = env("IMAGE_FAMILY")
}

variable "namespace" {
  type    = string
  default = env("namespace")
}
variable "os_type" {
  type    = string
  default = env("OS_TYPE")
}

variable "source_image_family" {
  type    = string
  default = env("SOURCE_IMAGE_FAMILY")
}

variable "project_id" {
  type    = string
  default = env("PROJECT_ID")
}

variable "subnet" {
  type    = string
  default = env("SUBNET")
}

variable "date_created" {
  type    = string
  default = env("DATE_CREATED")
}

variable "zone" {
  type    = string
  default = "us-east1-b"
}

variable "gim_family" {
  type    = string
  default = env("GIM_FAMILY")
}

variable "os_arch" {
  type    = string
  default = env("OS_ARCH")
}

variable "kms_key" {
  type    = string
  default = env("kms_key")
}

build {
  sources = [
    "source.googlecompute.gcp-ami"
  ]

  provisioner "file" {
    source = "certs"
    destination = "C:/Windows/system32"
  }

  provisioner "powershell" {
    script = "Windows_import_certs.ps1"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
  }

  provisioner "file" {
    source = "/tmp/UHG_Cloud_Windows_Server-snowagent-7.0.3-x64.msi"
    destination = "C:/Users/packer_user/UHG_Cloud_Windows_Server-snowagent-7.0.3-x64.msi"
  }
 
  provisioner "powershell" {
    inline = [
      "echo installing-snowagent",
      "dir",
      "msiexec /i UHG_Cloud_Windows_Server-snowagent-7.0.3-x64.msi /quiet"
    ]
  }
  
  provisioner "ansible" {
    max_retries   = 3
    playbook_file = "./ansible/playbook_win_gcp.yml"
    user          = "packer_user"
    use_proxy     = false
    extra_arguments = [
      "--tags", "${var.image_family}",
      "--extra-vars", "csp=gcp",
      "--extra-vars", "os_type=${var.os_type}",
      "--extra-vars", "image_family=${var.image_family}",
      "--extra-vars", "architecture=${var.os_arch}",
      "--extra-vars", "gcp_build_instance_id=${build.ID}",
      "--extra-vars", "namespace=${var.namespace}",
      "--extra-vars", "image_name=${var.namespace}${var.gim_family}-${var.date_created}",
      "--extra-vars", "date_created=${var.date_created}",
      "--extra-vars", "ansible_winrm_server_cert_validation=ignore"
    ]
  }

  provisioner "powershell" {
    inline = ["GCESysprep -NoShutdown"]
    skip_clean = true
  }
 
}

source "googlecompute" "gcp-ami" {
  project_id      = var.project_id
  zone            = var.zone
  machine_type    = "n1-standard-1"
  image_name      = "${var.namespace}${var.gim_family}-${var.date_created}"
  source_image_family    = var.source_image_family
  image_family        = var.gim_family
  image_labels        = {image_type: "golden-image"}
  disk_size       = 100
  subnetwork      = var.subnet
  omit_external_ip    = true
  use_internal_ip     = true
  use_iap      = true
  tags            = ["packer-build"]
  communicator    = "winrm"
  winrm_username  = "packer_user"
  winrm_insecure  = true
  winrm_use_ssl   = true
  image_encryption_key {
    kmsKeyName = var.kms_key
  }
  metadata = {    
    sysprep-specialize-script-cmd = "winrm quickconfig -quiet & net user /add packer_user & net localgroup administrators packer_user /add & winrm set winrm/config/service/auth @{Basic=\"true\"}"  
  }

}

