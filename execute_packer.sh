#!/bin/bash
set -e

# Define image families
IMAGE_FAMILIES=("rhel-family" "ubuntu-family" "windows-family")

# Update package lists and install Python3, wget, unzip
echo "Updating package lists and installing required packages..."
apt-get update -y
apt-get install python3 wget unzip -y

# Install Ansible
echo "Installing Ansible..."
apt-get install -y ansible

# Verify Ansible installation
ansible --version

# Install Packer
echo "Installing Packer..."
PACKER_VERSION="1.11.2"
wget "https://releases.hashicorp.com/packer/$PACKER_VERSION/packer_${PACKER_VERSION}_linux_amd64.zip"
unzip packer_${PACKER_VERSION}_linux_amd64.zip -d /usr/local/bin
/usr/local/bin/packer version  # Check the Packer version

# Unzip the Ansible playbook files
unzip ansible.zip -d ./ansible

# Print environment variables for debugging
echo "OS_TYPE: $OS_TYPE"
echo "IMAGE_FAMILY: $IMAGE_FAMILY"
echo "IMAGE_TYPE: $IMAGE_TYPE"
echo "IMAGE_PROJECT: $IMAGE_PROJECT"
echo "OS_ARCH: $OS_ARCH"
echo "DATE_CREATED: $DATE_CREATED"
echo "NETWORK: $NETWORK"
echo "SUBNET: $SUBNET"

# Loop through each image family and remove the "latest" label from all images
for FAMILY in "${IMAGE_FAMILIES[@]}"; do
    # List all images in the current family
    IMAGE_NAMES=$(gcloud compute images list \
        --filter="family=$FAMILY" \
        --format="value(name)")

    # Loop through each image in the family and remove the "latest" label
    for IMAGE in $IMAGE_NAMES; do
        echo "Removing 'latest' label from image: $IMAGE"
        gcloud compute images update "$IMAGE" --remove-labels=latest --quiet
    done
done

# Run Packer build
echo "Running Packer Build..."

# Determine which Packer file to use based on OS type and source image family
if [[ "$OS_TYPE" == "Windows" ]]; then
   PACKER_FILE="gcp_win.pkr.hcl"
else 
   PACKER_FILE="gcp.pkr.hcl"
fi

gsutil cp gs://gcp-build-bucket/UHG_Cloud* /tmp

# Initialize and build the chosen Packer file
/usr/local/bin/packer init "$PACKER_FILE"
/usr/local/bin/packer build "$PACKER_FILE"

# Sleep for 30 seconds to ensure resources are ready
sleep 30  

# Run metadata storage script
echo "Running store_metadata.py"
python3 store_metadata.py
