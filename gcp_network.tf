# VPC Network Creation
resource "google_compute_network" "gcp_build_network" {
  name                    = "${local.namespace-}gcp-build-network"
  auto_create_subnetworks = false
  project                 = var.project_id
}

# Subnet Creation
resource "google_compute_subnetwork" "gcp_build_subnet" {
  name          = "${local.namespace-}gcp-build-subnet"
  ip_cidr_range = var.subnet_cidr_range
  region        = var.region
  network       = google_compute_network.gcp_build_network.name
  project       = var.project_id
}

# Firewall 
resource "google_compute_firewall" "gcp_build_firewall" {
  name    = "${local.namespace-}packer-firewall"
  network = google_compute_network.gcp_build_network.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22", "5986"]
  }

  # Use tags for more specific rules as per your needs
  source_ranges = var.source_ranges
  target_tags   = var.target_tags
}

# Cloud Router
resource "google_compute_router" "gcp_build_router" {
  name    = "${local.namespace-}gcp-build-router"
  network = google_compute_network.gcp_build_network.name
  region  = var.region
  project = var.project_id
}

# Cloud NAT
resource "google_compute_router_nat" "gcp_build_nat" {
  name                               = "${local.namespace-}gcp-build-nat"
  router                             = google_compute_router.gcp_build_router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY" # Automatically assign external IPs
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ALL"
  }
}
