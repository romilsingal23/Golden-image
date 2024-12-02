resource "google_kms_key_ring" "key_ring" {
  name     = "example-key-ring"
  location = "us-central1"  # Replace with your preferred location
}

resource "google_kms_crypto_key" "crypto_key" {
  name     = "example-key"
  key_ring = google_kms_key_ring.key_ring.id
  purpose  = "ENCRYPT_DECRYPT"
}

resource "google_project_iam_member" "kms_permissions" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${var.packer_service_account}"
}
