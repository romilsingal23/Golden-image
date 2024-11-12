
packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable src_image {
  type    = string
  default = env("src_image")
}

locals {
  rand_src = uuidv4() # the only RNG packer can do is UUID generation, but UUIDs don't work as WINRM passwords
  winrm_password = "${upper(substr(local.rand_src, 0, 6))}#!${lower(substr(local.rand_src, 24, 6))}"
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
  type = string
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

build {
  sources = [
    "source.amazon-ebs.optum-ec2-ami"
  ]

  provisioner "powershell" {
    script            = "win_vuln_fix.ps1"
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
    inline =[
      "pwd",
      "msiexec /i UHG_Cloud_Windows_Server-snowagent-7.0.3-x64.msi /quiet"
    ]
  }

  provisioner "file" {
    source = "certs"
    destination = "C:/Windows/system32"
  }

  provisioner "powershell" {
    script            = "Windows_import_certs.ps1"
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
      "--extra-vars", "csp=aws",
      "--extra-vars", "namespace=${var.namespace}",
      "--extra-vars", "image_family=${var.image_family}",
      "--extra-vars", "architecture=${var.os_arch}",
      "--extra-vars", "aws_build_instance_id=${build.ID}",
      "--extra-vars", "ami_regions=${join(",", jsondecode(var.ami_regions))}",
      "--extra-vars", "os_type=${var.os_type}",
      "--extra-vars", "ami_name=${var.namespace-}optum/${var.image_family}_${var.date_created}",
      "--extra-vars", "src_img_id=${build.SourceAMI}",
      "--extra-vars", "src_img=${build.SourceAMIName}",
      "--extra-vars", "date_created=${var.date_created}",
      "--extra-vars", "ansible_winrm_server_cert_validation=ignore"
    ]
  }
}


source "amazon-ebs" "optum-ec2-ami" {
  ami_name             = "${var.namespace-}optum/${var.image_family}_${var.date_created}"
  ami_description      = "HCC Golden AMI for ${var.image_family}"
  region               = "us-east-1"
  instance_type        = "m5.large"
  sriov_support        = true
  ena_support          = true
  communicator         = "winrm"
  ssh_username         = "${var.ssh_user}"
  vpc_id               = "${var.vpc_id}"
  subnet_id            = "${var.subnet_id}"
  security_group_ids   = ["${var.security_group_id}"]
  iam_instance_profile = "${var.instance_profile}"
  ami_regions          = jsondecode(var.ami_regions)
  ami_org_arns         = jsondecode(var.org_arns)
  winrm_password       = "${local.winrm_password}"
  winrm_username       = "${var.ssh_user}"
  winrm_use_ssl        = true
  winrm_port           = 443
  winrm_insecure       = true
  winrm_timeout        = "10m"
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  aws_polling {
    delay_seconds = 50
    max_attempts  = 1000 
  }


  launch_block_device_mappings {
    device_name = "${var.os_root_volume}"
    encrypted   = true
    kms_key_id  = "${var.kms_id}"
    delete_on_termination = true
  }
  encrypt_boot = true
  region_kms_key_ids = var.kms_alias_map
  run_tags = local.build_tags
  tags = local.ami_tags

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

  user_data             = <<EOF
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
New-Item -Path WSMan:\LocalHost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $Cert.Thumbprint -Force

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
