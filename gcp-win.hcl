packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

variable "project_id" {
  type    = string
  default = "prj-ospacker-useast-dev-23295"
}

variable "subnet" {
  type    = string
  default = "projects/prj-shrd-ntwk-3/regions/us-east4/subnetworks/sn-ue4-ospac-dev-1"
}

variable "zone" {
  type    = string
  default = "us-east4-a"
}

build {
  sources = ["source.googlecompute.Windows2025-Server", "source.googlecompute.Windows2022-Server"]

  provisioner "windows-restart" {}

  provisioner "file" {
    source      = "windows-scripts/windows2022/"
    destination = "C:/temp/"
  }

  provisioner "windows-shell" {
    script = "windows-scripts/windows2022/Packer.bat"
  }

}

source "googlecompute" "Windows2025-Server" {
  project_id          = var.project_id
  zone                = var.zone
  machine_type        = "n1-standard-1"
  image_name          = "windows-2025-${local.timestamp}"
  source_image_family = "windows-2025"
  image_family        = "windows-2025-family"
  image_labels        = { image_type : "golden-image" }
  image_storage_locations = ["us-east4"]
  disk_size           = 100
  subnetwork          = var.subnet
  omit_external_ip    = true
  use_internal_ip     = true
  use_iap             = true
  tags                = ["us-east4"]
  communicator        = "winrm"
  winrm_username      = "packer_user"
  winrm_insecure      = true
  winrm_use_ssl       = true
  disk_encryption_key {
	kmsKeyName = "projects/prj-shrd-secu-5/locations/us-east4/keyRings/cmdk-key-ring/cryptoKeys/cmek-key/cryptoKeyVersions/1"
	}
  image_encryption_key {
	kmsKeyName = "projects/prj-shrd-secu-5/locations/us-east4/keyRings/cmdk-key-ring/cryptoKeys/cmek-key/cryptoKeyVersions/1"
	}
  labels = {
    appserviceid = "tbd"
    appservicename = "gcp"
    timestamp= "tbd"
    iac = "packer"
    datatype = "tbd"
    costcenter = "tbd"
    tierid = "tier-1"
  }  
  metadata = {
   sysprep-specialize-script-cmd = "winrm quickconfig -quiet & net user /add packer_user & net localgroup administrators packer_user /add & winrm set winrm/config/service/auth @{Basic=\"true\"}"
  }
}

source "googlecompute" "Windows2022-Server" {
  project_id          = var.project_id
  zone                = var.zone
  machine_type        = "n1-standard-1"
  image_name          = "windows-2022-${local.timestamp}"
  source_image_family = "windows-2022"
  image_family        = "windows-2022-family"
  image_labels        = { image_type : "golden-image" }
  image_storage_locations = ["us-east4"]
  disk_size           = 100
  subnetwork          = var.subnet
  omit_external_ip    = true
  use_internal_ip     = true
  use_iap             = true
  tags                = ["packer-build"]
  disk_encryption_key {
	kmsKeyName = "projects/prj-shrd-secu-5/locations/us-east4/keyRings/cmdk-key-ring/cryptoKeys/cmek-key/cryptoKeyVersions/1"
	}
  image_encryption_key {
	kmsKeyName = "projects/prj-shrd-secu-5/locations/us-east4/keyRings/cmdk-key-ring/cryptoKeys/cmek-key/cryptoKeyVersions/1"
	}
  communicator        = "winrm"
  winrm_username      = "packer_user"
  winrm_insecure      = true
  winrm_use_ssl       = true
  labels = {
    appserviceid = "tbd"
    appservicename = "gcp"
    timestamp= "tbd"
    iac = "packer"
    datatype = "tbd"
    costcenter = "tbd"
    tierid = "tier-1"
  }  
  metadata = {
    sysprep-specialize-script-cmd = "winrm quickconfig -quiet & net user /add packer_user & net localgroup administrators packer_user /add & winrm set winrm/config/service/auth @{Basic=\"true\"}"
  }
}
