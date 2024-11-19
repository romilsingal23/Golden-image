# Configure the GCP provider
provider "google" {
  project = "your-gcp-project-id"
  region  = "us-central1"
}

# Fetch AWS Access Key from GCP Secret Manager
data "google_secret_manager_secret_version" "aws_access_key" {
  secret = "aws-access-key"   # The name of the secret in GCP
  version = "latest"
}

# Fetch AWS Secret Key from GCP Secret Manager
data "google_secret_manager_secret_version" "aws_secret_key" {
  secret = "aws-secret-key"   # The name of the secret in GCP
  version = "latest"
}

# AWS Provider configuration
provider "aws" {
  region     = "us-east-1"
  access_key = data.google_secret_manager_secret_version.aws_access_key.secret_data
  secret_key = data.google_secret_manager_secret_version.aws_secret_key.secret_data
}
