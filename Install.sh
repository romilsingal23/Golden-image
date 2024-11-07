#!/bin/bash

# Exit on any error
set -e

# Step 1: Install Packer
echo "Installing Packer..."
curl -qL -o packer.zip https://releases.hashicorp.com/packer/1.8.2/packer_1.8.2_linux_amd64.zip
unzip packer.zip
mv packer /usr/local/bin/packer
packer version

# Step 2: Install Terraform (if needed)
echo "Installing Terraform..."
curl -qL -o terraform.zip https://releases.hashicorp.com/terraform/1.2.3/terraform_1.2.3_linux_amd64.zip
unzip terraform.zip
mv terraform /usr/local/bin/terraform
terraform version

# Step 3: Install Ansible and other dependencies
echo "Installing Ansible and Python dependencies..."
pip install ansible==2.10 requests loguru pywinrm pyyaml aws_requests_auth azure.identity azure.storage.blob
ansible --version

# Step 4: Run execute_packer.sh (make sure it's executable)
echo "Running execute_packer.sh..."
chmod +x ./execute_packer.sh
./execute_packer.sh

# Step 5: Deploy the Cloud Function
echo "Deploying Cloud Function..."
gcloud functions deploy my-cloud-function \
  --region=us-east1 \
  --runtime=python310 \
  --trigger-http \
  --allow-unauthenticated \
  --source=. \
  --entry-point=main
