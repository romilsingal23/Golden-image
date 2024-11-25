# Cloud Router
resource "google_compute_router" "gcp_build_router" {
  name    = "${local.namespace}-gcp-build-router"
  network = google_compute_network.gcp_build_network.name
  region  = var.region
  project = var.project_id
}

# Cloud NAT
resource "google_compute_router_nat" "gcp_build_nat" {
  name                       = "${local.namespace}-gcp-build-nat"
  router                     = google_compute_router.gcp_build_router.name
  region                     = var.region
  project                    = var.project_id
  nat_ip_allocate_option     = "AUTO_ONLY" # Automatically assign external IPs
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Optional: Customize NAT configurations
  log_config {
    enable = true
    filter = "ALL"
  }
}
