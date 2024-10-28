# VPC Network Creation
resource "google_compute_network" "build_network" {
  count      = local.is_local ? 0 : 1
  name       = local.build_name
  auto_create_subnetworks = false
  project    = var.project_id
}

# Subnet Creation
resource "google_compute_subnetwork" "build_network" {
  for_each   = {
    "${local.build_name}" : local.subnet_range
  }
  name       = each.key
  ip_cidr_range = each.value
  region     = var.region
  network    = google_compute_network.build_network[0].name
  project    = var.project_id
}

# Firewall (equivalent to Network Security Group)
resource "google_compute_firewall" "build_network" {
  name       = local.build_name
  network    = google_compute_network.build_network[0].name
  project    = var.project_id

  # Example firewall rule allowing SSH; adjust to your rules
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  # Use tags for more specific rules as per your needs
  target_tags = ["ssh-allowed"]
}
