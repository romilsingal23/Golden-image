packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/azure"
    }
  }
}

variable "sub_id" {
  type    = string
  default = env("SUB_ID")
}

variable "azu_rg_name" {
  type    = string
  default = env("azu_rg_name")
}

variable "managed_identity" {
  type    = string
  default = env("managed_identity")
}

variable "namespace" {
  type    = string
  default = env("namespace")
}

variable "image_version" {
  type    = string
  default = env("image_version")
}

variable "image_family" {
  type    = string
  default = env("image_family")
}

variable "infra_name" {
  type    = string
  default = env("infra_name")
}

variable "gallery_name" {
  type    = string
  default = env("gallery_name")
}

variable "os_type" {
  type    = string
  default = env("os_type")
}

variable "image_publisher" {
  type    = string
  default = env("image_publisher")
}

variable "image_offer" {
  type    = string
  default = env("image_offer")
}

variable "image_sku" {
  type    = string
  default = env("image_sku")
}

variable "version" {
  type    = string
  default = env("version")
}

variable "expire_date" {
  type    = string
  default = env("expire_date")
}

variable "date_created" {
  type    = string
  default = env("date_created")
}

variable "storage_account" {
  default = env("PK_VAR_storage_account")
}

variable "gallery_resource_group" {
  default = env("PK_VAR_gallery_resource_group")
}

variable "regions" {
  type    = string
  default = env("regions")
}

variable "capture_name_prefix" {
  type    = string
  default = env("capture_name_prefix")
}

locals{
  image_tags = {
    "OSDistribution" = "${var.image_family}"
    "Contact"        = "HCC_CDTK@ds.uhc.com"
    "AppName"        = "CDTK Golden Images"
    "CostCenter"     = "44770-01508-USAMN022-160465"
    "AIDE_ID"        = "AIDE_0077829"
    "SCM"            = "https://github.com/optum-eeps/hcc_lp_golden_image_bakery"
    "ImageType"      = "ApprovedOptumGoldenImage"
  }
}

source "azure-arm" "image" {

  os_type                                = var.os_type
  image_version                          = var.image_version
  image_publisher                        = var.image_publisher
  image_offer                            = var.image_offer
  image_sku                              = var.image_sku
  build_resource_group_name              = var.azu_rg_name
  vm_size                                = "Standard_B2s"
  virtual_network_name                   = var.azu_rg_name
  virtual_network_subnet_name            = var.infra_name
  virtual_network_resource_group_name    = var.azu_rg_name
  azure_tags                             = local.image_tags
  user_assigned_managed_identities       = [var.managed_identity]
  shared_image_gallery_destination {
    subscription         = var.sub_id
    resource_group       = var.gallery_name
    gallery_name         = var.gallery_name
    image_name           = var.image_family
    image_version        = var.version
    replication_regions  = jsondecode(var.regions)
    storage_account_type = "Standard_LRS"
  }
  shared_gallery_image_version_end_of_life_date = "${var.expire_date}T00:00:00.00Z"
  managed_image_name                            = var.image_family
  managed_image_resource_group_name             = var.gallery_name
}

source "azure-arm" "image_backup" {
  user_assigned_managed_identities       = [var.managed_identity]

  os_type                                = var.os_type
  image_version                          = var.image_version
  image_publisher                        = var.image_publisher
  image_offer                            = var.image_offer
  image_sku                              = var.image_sku
  build_resource_group_name              = var.azu_rg_name
  vm_size                                = "Standard_B2s"
  virtual_network_name                   = var.azu_rg_name
  virtual_network_subnet_name            = var.infra_name
  virtual_network_resource_group_name    = var.azu_rg_name
  capture_container_name                 = "gallery-backup"
  capture_name_prefix                    = var.capture_name_prefix
  resource_group_name                    = var.gallery_resource_group
  storage_account                        = var.storage_account
}

build {
 
  source "azure-arm.image" {
    name= "image-version"
  }

  source "azure-arm.image_backup" {
    name= "image-backup"
  }

  provisioner "shell" {
    expect_disconnect = true
    script            = "updates.sh"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
    pause_after       = "5m"
  }
  
  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "if [ \"${var.image_family}\" == \"Ubuntu_20\" ]; then",
      "echo UpgradingOpenSSH",
      "sudo apt-get update --fix-missing",
      "sudo apt install -y zlib1g-dev",
      "sudo apt install -y libssl-dev",
      "sudo apt-get install -y build-essential",
      "sudo apt-get install -y manpages-dev",
      "sudo mkdir /var/lib/sshd",
      "sudo chmod -R 700 /var/lib/sshd/",
      "sudo chown -R root:sys /var/lib/sshd/",
      "wget -c https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.0p1.tar.gz",
      "tar -xzf openssh-9.0p1.tar.gz",
      "cd openssh-9.0p1/",
      "sudo apt install -y libpam0g-dev",
      "sudo apt install -y libselinux1-dev",
      "./configure --with-md5-passwords --with-pam --with-selinux --with-privsep-path=/var/lib/sshd/ --sysconfdir=/etc/ssh",
      "make",
      "sudo make install",
      "sudo systemctl restart ssh",
      "echo aptUpdating",
      "sudo apt -y update",
      "fi"
    ]
    execute_command   = "{{.Vars}} bash '{{.Path}}'"
    pause_after       = "5m"
  }

  provisioner "file" {
    source = "certs"
    destination = "/tmp/"
  }

  provisioner "shell" {
    script            = "linux_certs_upload.sh"
    environment_vars = [
      "image_family=${var.image_family}"
    ]
  }

  provisioner "file" {
    sources = ["UHG_Cloud_Linux_Server-snowagent-7.0.1-x64.deb","UHG_Cloud_Linux_Server-snowagent-7.0.1-x64.rpm"]
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
    user          = "azureuser"
    extra_arguments = [
      "--tags", "${var.image_family}",
      "--extra-vars", "csp=azu",
      "--extra-vars", "source_name=${source.name}",
      "--extra-vars", "namespace=${var.namespace}",
      "--extra-vars", "os_type=${var.os_type}",
      "--extra-vars", "image_family=${var.image_family}",
      "--extra-vars", "image_name=${var.image_family}",
      "--extra-vars", "image_offer=${var.image_offer}",
      "--extra-vars", "image_sku=${var.image_sku}",
      "--extra-vars", "image_version=${var.version}",
      "--extra-vars", "date_created=${var.date_created}"
    ]
  }

  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "if [ \"${var.image_family}\" == \"RHEL_9\" ]; then",
      "sudo rpm -e --nodeps python3-setuptools-wheel",
      "sudo rpm -e --nodeps python3-setuptools",
      "sudo rpm -e --nodeps python39-setuptools-wheel",
      "sudo rpm -e --nodeps python39-setuptools",
      "sudo rpm -e --nodeps linux-firmware",
      "sudo rpm -e --nodeps python3-oauthlib",
      "sudo yum -y remove python3-perf",
      "sudo yum -y remove wget",
      "sudo yum -y remove linux-firmware",
      "sudo rpm -e --nodeps fuse-libs",
      "sudo yum -y remove sssd-client",
      "sudo rpm -e --nodeps python3-babel",
      "sudo rpm -e --nodeps libarchive",
      "sudo yum -y remove linux-firmware-whence",
      "fi"
    ]
    execute_command   = "{{.Vars}} bash '{{.Path}}'"
    pause_after       = "2m"
  }
  
  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "if [ \"${var.image_family}\" == \"Ubuntu_22\" ]; then",
      "sudo apt -y remove dmidecode", # removable
      "sudo apt -y autoremove --purge policykit-1",
      "sudo apt -y autoremove libpolkit-gobject-1-0",
      "sudo apt -y autoremove git",
      "sudo apt -y remove libbluetooth3", # removable bluez
      "sudo apt-get -y remove binutils*",# removable
      "sudo apt -y autoremove libwbclient0", # removable samba
      "sudo apt -y remove patch", # removable
      "sudo apt -y remove python3-httplib2", # removable
      # " sudo apt -y autoremove libyaml-0-2",
      # "sudo apt autoremove -y apparmor",
      "sudo apt -y autoremove --purge snapd",
      "sudo apt-get remove --purge -y linux-tools-common",
      "sudo apt-get remove --purge -y linux-cloud-tools-common",
      # "sudo dpkg --remove --force-depends libapparmor1",
      "sudo apt -y autoremove --purge python3-twisted",
      "sudo apt -y autoremove --purge wpasupplicant",
      "fi"
    ]
    execute_command   = "{{.Vars}} bash '{{.Path}}'"
    pause_after       = "2m"
  }
  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "if [ \"${var.image_family}\" == \"Ubuntu_20\" ]; then",
      "sudo apt-get remove --purge -y wpa*",
      "sudo apt-get remove --purge -y policykit*",
      "sudo apt -y autoremove libwbclient0",
      "sudo apt -y autoremove libpolkit-gobject-1-0",
      "sudo apt -y autoremove dmidecode",
      "sudo apt -y remove htop",
      "sudo apt -y remove python3-httplib2",
      # "sudo apt-get remove --purge -y libyaml*",
      "sudo apt-get remove --purge -y git*",
      "sudo apt-get remove --purge -y glibc*",
      "sudo apt-get remove --purge -y binutils*",
      "sudo apt-get remove --purge -y pptp-linux*",
      # "sudo apt-get autoremove --purge -y apparmor*",
      "sudo apt -y autoremove --purge snapd",
      # "sudo dpkg --remove --force-depends libapparmor1",
      "sudo apt-get remove --purge -y linux-tools-common",
      "sudo apt-get remove --purge -y linux-cloud-tools-common",
      "sudo apt-get remove --purge -y linux-libc-dev",
      "sudo apt -y autoremove --purge python3-twisted",
      "fi"
    ]
    execute_command   = "{{.Vars}} bash '{{.Path}}'"
    pause_after       = "2m"
  }
}
