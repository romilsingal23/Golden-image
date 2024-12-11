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

#
# Standard test module
#

module "helpers" {
  source           = "../modules/test_helpers"
  policy_folder    = "standard"
  policy_file_name = "custom.disableVmNestedVirtualization.json"
}

#
# Policy
#

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

#
# Time sleep - wait for policy to be enforced after creation
#

resource "time_sleep" "wait" {
  create_duration = "120s"

  depends_on = [
    module.gcp_policy.org_policy,
    module.gcp_policy.constraint
  ]
}
# Important: Make sure to add depends_on to the resources that are created after the policy
#
# Compliant tests
#


resource "google_compute_instance" "compliant_explicit" {
    name         = "my-compliant-explicit-instance-555"
    zone             = "us-central1-a"
    machine_type     = "n2d-standard-2"
    min_cpu_platform = "AMD Milan"

    confidential_instance_config {
        enable_confidential_compute = true
    }

    boot_disk {
        initialize_params {
        image = "ubuntu-os-cloud/ubuntu-2004-lts"
        labels = {
            my_label = "value"
        }
        }
    }

    network_interface {
        network = "default"
    }
    advanced_machine_features {
        enable_nested_virtualization = false
    }

    metadata_startup_script = "echo hi > /test.txt"
    depends_on = [ time_sleep.wait ]
}


resource "google_compute_instance" "compliant_default" {
    name         = "my-compliant-default-instance-555"
    zone             = "us-central1-a"
    machine_type     = "n2d-standard-2"
    min_cpu_platform = "AMD Milan"

    confidential_instance_config {
        enable_confidential_compute = true
    }

    boot_disk {
        initialize_params {
        image = "ubuntu-os-cloud/ubuntu-2004-lts"
        labels = {
            my_label = "value"
        }
        }
    }

    network_interface {
        network = "default"
    }
    # advanced_machine_features {     # Addvanced machine features can't be defined without enable_nested_virtualization
    #     # enable_nested_virtualization = false
    # }

    metadata_startup_script = "echo hi > /test.txt"
    depends_on = [ time_sleep.wait ]
}

#
# Non Compliant tests
#

# Expect to see: Error: googleapi: Error 400: Operation denied by custom org policy: [<CONSTRAINT_NAME>: <DESCRIPTION>
# Or if you still have a manually deployed version Error: googleapi: Error 412: Multiple constraints were violated. See details for more information. 

resource "google_compute_instance" "non_compliant" {
    name         = "my-non-compliant-instance-555"
    zone             = "us-central1-a"
    machine_type     = "n2d-standard-2"
    min_cpu_platform = "AMD Milan"

    confidential_instance_config {
        enable_confidential_compute = true
    }

    boot_disk {
        initialize_params {
        image = "ubuntu-os-cloud/ubuntu-2004-lts"
        labels = {
            my_label = "value"
        }
        }
    }

    network_interface {
        network = "default"
    }
    advanced_machine_features {
        enable_nested_virtualization = true
        # threads_per_core = 1
    }

    metadata_startup_script = "echo hi > /test.txt"
    depends_on = [ time_sleep.wait ]
}
