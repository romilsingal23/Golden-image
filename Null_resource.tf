resource "null_resource" "delete_packages" {
  provisioner "local-exec" {
    command = "bash ${path.module}/delete_packages.sh ${var.project_id} us-east1 gcf-artifacts"
  }

  triggers = {
    timestamp = timestamp() # Ensure it runs every time
  }
}
