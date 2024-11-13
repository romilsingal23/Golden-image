variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

source "googlecompute" "windows" {
  project_id             = var.project_id
  source_image_family    = "windows-2016"
  disk_size              = 100
  disk_type              = "pd-ssd"
  machine_type           = "n1-standard-2"
  communicator           = "winrm"
  subnetwork             = "app-vms"
  tags                   = ["packer-winrm"]
  winrm_username         = "packer_user"
  winrm_insecure         = true
  winrm_use_ssl          = true
  metadata = {
    "windows-startup-script-cmd" = <<-EOF
      winrm quickconfig -quiet
      net user /add packer_user
      net localgroup administrators packer_user /add
      winrm set winrm/config/service/auth @{Basic="true"}
    EOF
  }
  zone                   = "europe-west2-a"
  image_storage_locations = ["europe-west2"]
  image_name             = "app-{{timestamp}}"
  image_family           = "app-base"
}

build {
  sources = ["source.googlecompute.windows"]

  provisioner "powershell" {
    script = "packer/app.ps1"
  }
}
