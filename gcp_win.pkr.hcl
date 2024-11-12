packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "src_image" {
  type    = string
  default = env("src_image")
}

locals {
  rand_src = uuidv4()
  winrm_password = "${upper(substr(local.rand_src, 0, 6))}#!${lower(substr(local.rand_src, 24, 6))}"
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
  default = env("image_family")
}

variable "project_id" {
  type    = string
  default = env("GCP_PROJECT_ID")
}

variable "subnet" {
  type    = string
  default = env("subnet")
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

build {
  sources = [
    "source.googlecompute.gcp-ami"
  ]

  provisioner "powershell" {
    script = "win_vuln_fix.ps1"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
  }

  provisioner "windows-restart" {
    restart_check_command = "powershell -command \"& {Write-Output 'restarted.'}\""
  }
  
  provisioner "file" {
    source = "/tmp/UHG_Cloud_Windows_Server-snowagent-7.0.3-x64.msi"
    destination = "C:/Users/Ansible/UHG_Cloud_Windows_Server-snowagent-7.0.3-x64.msi"
  }

  provisioner "powershell" {
    inline = [
      "pwd",
      "msiexec /i UHG_Cloud_Windows_Server-snowagent-7.0.3-x64.msi /quiet"
    ]
  }

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
   
  provisioner "ansible" {
    max_retries   = 3
    playbook_file = "./ansible/playbook_win_aws.yml"
    user          = "${var.ssh_user}"
    use_proxy     = false
    extra_arguments = [
      "--tags", "${var.image_family}",
      "--extra-vars", "csp=gcp",
      "--extra-vars", "namespace=${var.namespace}",
      "--extra-vars", "image_family=${var.image_family}",
      "--extra-vars", "architecture=${var.os_arch}",
      "--extra-vars", "gcp_build_instance_id=${build.ID}",
      "--extra-vars", "ami_name=${var.namespace}-optum/${var.image_family}_${var.date_created}",
      "--extra-vars", "src_img_id=${build.SourceImageId}",
      "--extra-vars", "src_img=${build.SourceImageName}",
      "--extra-vars", "date_created=${var.date_created}",
      "--extra-vars", "ansible_winrm_server_cert_validation=ignore"
    ]
  }
}

source "googlecompute" "gcp-ami" {
  project_id      = var.project_id
  source_image    = var.src_image
  zone            = var.zone
  machine_type    = "n1-standard-1"
  image_name      = "${var.namespace}-optum-${var.image_family}-${var.date_created}"
  image_family    = var.image_family
  network         = "global/networks/default"
  subnetwork      = var.subnet
  tags            = ["http-server", "https-server"]

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<EOF
# Powershell script for configuring WinRM, etc.
<powershell>
# Create username and password
net user Ansible ${local.winrm_password} /add
wmic useraccount where "name='Ansible'" set PasswordExpires=FALSE
net localgroup Administrators Ansible /add
net localgroup "Remote Desktop Users" Ansible /add

Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Ignore

# Don't set this before Set-ExecutionPolicy as it throws an error
$ErrorActionPreference = "stop"

# save current hostname
$CurrentHostname = hostname

# Remove HTTP listener
Remove-Item -Path WSMan:\Localhost\listener\listener* -Recurse

# Create a self-signed certificate to let ssl work
$Cert = New-SelfSignedCertificate -CertstoreLocation Cert:\LocalMachine\My -DnsName "$CurrentHostname"
New-Item -Path WSMan:\LocalHost\Listener -Transport HTTPS -Address * -CertificateThumbprint $Cert.Thumbprint -Force

# WinRM
write-output "Setting up WinRM"
write-host "(host) setting up WinRM"

# Configure WinRM to allow unencrypted communication, and provide the
# self-signed cert to the WinRM listener.
cmd.exe /c winrm quickconfig -q
cmd.exe /c winrm set "winrm/config/service" '@{AllowUnencrypted="true"}'
cmd.exe /c winrm set "winrm/config/client" '@{AllowUnencrypted="true"}'
cmd.exe /c winrm set "winrm/config/service/auth" '@{Basic="true"}'
cmd.exe /c winrm set "winrm/config/client/auth" '@{Basic="true"}'
cmd.exe /c winrm set "winrm/config/service/auth" '@{CredSSP="true"}'
cmd.exe /c winrm set "winrm/config/listener?Address=*+Transport=HTTPS" "@{Port=`"443`";Hostname=`"$CurrentHostname`";CertificateThumbprint=`"$($Cert.Thumbprint)`"}"

# Make sure appropriate firewall port openings exist
cmd.exe /c netsh advfirewall firewall set rule group="remote administration" new enable=yes
cmd.exe /c netsh firewall add portopening TCP 443 "Port 443"

# Restart WinRM, and set it so that it auto-launches on startup.
cmd.exe /c net stop winrm
cmd.exe /c sc config winrm start= auto
cmd.exe /c net start winrm
</powershell>
EOF
}
