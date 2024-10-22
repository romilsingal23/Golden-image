variable "project_id" {
  description = "The ID of the GCP project."
  type        = string
}

variable "region" {
  description = "The region where resources will be created."
  type        = string
  default     = "us-east1"  # Set your default region
}

variable "vpc_name" {
  description = "The name of the VPC network."
  type        = string
  default     = "myvpc1"
}

variable "subnet_name" {
  description = "The name of the subnet."
  type        = string
  default     = "subnet2"
}

variable "service_account_name" {
  description = "The name for the service account."
  type        = string
  default     = "golden-vm-sa"
}

variable "cloud_function_bucket" {
  description = "The name of the Cloud Storage bucket for Cloud Function."
  type        = string
}

variable "cloud_function_name" {
  description = "The name of the Cloud Function for image lifecycle management."
  type        = string
  default     = "image-lifecycle-function"
}

variable "tags" {
  description = "Tags for the golden VM."
  type        = list(string)
  default     = ["golden-vm"]
}

variable "labels" {
  description = "Labels for the Cloud Function."
  type        = map(string)
  default     = {
    environment = "production"
    managed_by   = "terraform"
  }
}
