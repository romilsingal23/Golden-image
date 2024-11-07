resource "google_cloudfunctions_function" "my_cloud_function" {
  name        = "my-cloud-function"
  description = "Cloud Function to trigger Packer build"
  runtime     = "python39"
  entry_point = "main"

  available_memory_mb = 256
  timeout             = 540

  # Define your environment variables here
  environment_variables = {
    namespace      = "my_namespace"
    namespacedash  = "my-namespace-dash"
    image_family   = "ubuntu-20-04"
    os_owner       = "google"
    os_name        = "ubuntu-20-04"
    os_type        = "ubuntu"
    os_arch        = "x86_64"
    ssh_user       = "ubuntu"
    network        = "default"
    subnet         = "default"
    kms_key        = "projects/my-project-id/locations/us-central1/keyRings/my-keyring/cryptoKeys/my-key"
    project_id     = "my-project-id"
    date_created   = "2024-11-07"
  }

  source_archive_bucket = "your-bucket-name"
  source_archive_object = "your-cloud-function-zip-file.zip"
}
