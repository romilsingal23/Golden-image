output "service_account_email" {
  description = "Email of the created service account."
  value       = google_service_account.golden_vm_service_account.email
}

output "cloud_function_url" {
  description = "URL of the Cloud Function for lifecycle management."
  value       = google_cloudfunctions_function.lifecycle_handler.https_trigger_url
}

output "golden_vm_instance_name" {
  description = "Name of the created golden VM instance."
  value       = google_compute_instance.golden_vm.name
}

output "vpc_network_name" {
  description = "Name of the created VPC network."
  value       = google_compute_network.myvpc.name
}

output "subnetwork_name" {
  description = "Name of the created subnet."
  value       = google_compute_subnetwork.my_subnet.name
}
