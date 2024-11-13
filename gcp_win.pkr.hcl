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

variable "namespace" {
  type    = string
  default = env("namespace")
}

variable "source_image_family" {
  type    = string
  default = env("SOURCE_IMAGE_FAMILY")
}

locals {
  rand_src      = uuidv4()
  namespace     = "dev"
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

variable "image_project" {
  type    = string
  default = env("IMAGE_PROJECT")
}

variable "project_id" {
  type    = string
  default = env("PROJECT_ID")
}

variable "subnet" {
  type    = string
  default = env("SUBNET")
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "date_created" {
  type    = string
  default = env("DATE_CREATED")
}

variable "zone" {
  type    = string
  default = "us-east1-b"
}

variable "os_arch" {
  type    = string
  default = env("OS_ARCH")
}

build {
  sources = [
    "source.googlecompute.gcp-ami"
  ]

  provisioner "powershell" {
    script = "configure_winrm_and_cert.ps1"  # Combined PowerShell tasks for WinRM and certificates
    environment_vars = [
      "image_family=${var.image_family}"
    ]
  }

  provisioner "windows-restart" {
    restart_check_command = "powershell -command \"& {Write-Output 'restarted.'}\""
  }

  provisioner "file" {
    source      = "certs"
    destination = "C:/Windows/system32"
  }

  provisioner "ansible" {
    max_retries    = 3
    playbook_file  = "./ansible/playbook_win_aws.yml"
    user           = "Ansible"  # Keep the username for WinRM configuration
    use_proxy      = false
    extra_arguments = [
      "--extra-vars", "@extra_vars.yml"
    ]
  }
}

source "googlecompute" "gcp-ami" {
  project_id      = var.project_id
  zone            = var.zone
  machine_type    = "n1-standard-1"
  image_name      = "${local.namespace}-optum-${var.source_image_family}"
  source_image_family    = var.source_image_family
  disk_size       = 50
  subnetwork      = var.subnet
  tags            = ["packer-winrm"]
  communicator    = "winrm"
  winrm_username  = "Ansible"
  winrm_insecure  = true
  winrm_use_ssl   = true

  metadata = {
    "windows-startup-script-cmd" = <<-EOF
      # PowerShell script for configuring WinRM and SSL certificates
      
      # Create user and set password if not already created
      if (-not (Get-LocalUser "Ansible")) {
        net user Ansible ${local.winrm_password} /add
        net localgroup Administrators Ansible /add
      }

      # Disable password expiration
      wmic useraccount where "name='Ansible'" set PasswordExpires=FALSE

      # Set Execution Policy
      Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Ignore

      # Setup SSL certificate for WinRM
      $CurrentHostname = hostname
      $Cert = New-SelfSignedCertificate -CertstoreLocation Cert:\LocalMachine\My -DnsName "$CurrentHostname"
      New-Item -Path WSMan:\LocalHost\Listener -Transport HTTPS -Address * -CertificateThumbprint $Cert.Thumbprint -Force

      # Setup WinRM configuration
      winrm quickconfig -q
      winrm set "winrm/config/service" '@{AllowUnencrypted="true"}'
      winrm set "winrm/config/client" '@{AllowUnencrypted="true"}'
      winrm set "winrm/config/service/auth" '@{Basic="true"}'
      winrm set "winrm/config/client/auth" '@{Basic="true"}'
      winrm set "winrm/config/service/auth" '@{CredSSP="true"}'
      winrm set "winrm/config/listener?Address=*+Transport=HTTPS" "@{Port=`"443`";Hostname=`"$CurrentHostname`";CertificateThumbprint=`"$($Cert.Thumbprint)`"}"

      # Open necessary ports in Windows Firewall
      netsh advfirewall firewall set rule group="remote administration" new enable=yes
      netsh firewall add portopening TCP 443 "Port 443"

      # Restart WinRM service to apply settings
      net stop winrm
      sc config winrm start= auto
      net start winrm
    EOF
  }
}
