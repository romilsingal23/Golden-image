terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.29.1"
    }
  }
  required_version = ">= 1.9.5"
}

provider "google" {
  project = "pc-insights-dev"
  region  = "us-central1"

  user_project_override = true
  billing_project       = "pc-insights-dev"
}

module "helpers" {
  source           = "../modules/test_helpers"
  policy_folder    = "standard"
  policy_file_name = "custom.blockRedHat9Windows22Images.json"  # Path to the policy file
}

module "gcp_policy" {
  source                   = "../../modules/org_policy_v2"
  folder_name              = ""
  folder_display_name      = module.helpers.folder_display_name
  organization_name        = module.helpers.organization.name
  policy_json              = module.helpers.json_data
  assignment_override      = "projects/${module.helpers.project.project_id}"
  override_spec            = true
  constraint_name_override = module.helpers.constraint_name
}

resource "time_sleep" "wait" {
  create_duration = "120s"

  depends_on = [
    module.gcp_policy.org_policy,
    module.gcp_policy.constraint
  ]
}

#
# Compliant Test: Instances with allowed images
#

resource "google_compute_instance" "compliant_explicit" {
  name               = "my-compliant-explicit-instance-555"
  zone               = "us-central1-a"
  machine_type       = "n2d-standard-2"
  min_cpu_platform   = "AMD Milan"

  confidential_instance_config {
    enable_confidential_compute = true
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"  # A compliant image (Ubuntu)
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = "echo hi > /test.txt"
  depends_on = [time_sleep.wait]
}

#
# Non-Compliant Test: Instances with restricted images (RHEL 9 or Windows 2022)
#

resource "google_compute_instance" "non_compliant_rhel9" {
  name               = "my-non-compliant-instance-rhel9-555"
  zone               = "us-central1-a"
  machine_type       = "n2d-standard-2"
  min_cpu_platform   = "AMD Milan"

  confidential_instance_config {
    enable_confidential_compute = true
  }

  boot_disk {
    initialize_params {
      image = "projects/rhel-cloud/global/images/family/rhel-9"  # A restricted image (RHEL 9)
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = "echo hi > /test.txt"
  depends_on = [time_sleep.wait]
}

resource "google_compute_instance" "non_compliant_windows2022" {
  name               = "my-non-compliant-instance-windows2022-555"
  zone               = "us-central1-a"
  machine_type       = "n2d-standard-2"
  min_cpu_platform   = "AMD Milan"

  confidential_instance_config {
    enable_confidential_compute = true
  }

  boot_disk {
    initialize_params {
      image = "projects/windows-cloud/global/images/family/windows-2022"  # A restricted image (Windows Server 2022)
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = "echo hi > /test.txt"
  depends_on = [time_sleep.wait]
}
