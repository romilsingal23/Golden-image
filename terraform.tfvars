project_id         = "consumer-project-431315"
region             = "us-east1"
vpc_name           = "myvpc1"
subnet_name        = "subnet2"
service_account_name = "golden-vm-service-account"
cloud_function_bucket = "your-bucket-name"
cloud_function_name = "lifecycle_handler"
image_family       = "golden-image-family"
tags               = ["golden-vm"]
labels = {
  "created_by" = "terraform"
  "version"    = "1.0"
}
