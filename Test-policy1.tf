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
  policy_file_name = "custom.blockUntrustedImageProjects.json"  # Path to the policy file
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
# Compliant Test: Instances with allowed images from the trusted image project
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
      image = "projects/trusted-project/global/images/my-trusted-image"  # A compliant image from the trusted project
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = "echo hi > /test.txt"
  depends_on = [time_sleep.wait]
}

#
# Non-Compliant Test: Instances with untrusted images (images from untrusted projects)
#

resource "google_compute_instance" "non_compliant_untrusted" {
  name               = "my-non-compliant-instance-untrusted-555"
  zone               = "us-central1-a"
  machine_type       = "n2d-standard-2"
  min_cpu_platform   = "AMD Milan"

  confidential_instance_config {
    enable_confidential_compute = true
  }

  boot_disk {
    initialize_params {
      image = "projects/untrusted-project/global/images/my-untrusted-image"  # A non-compliant image from an untrusted project
    }
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = "echo hi > /test.txt"
  depends_on = [time_sleep.wait]
}
