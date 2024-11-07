#!/bin/bash
set -e

# Deploys an image on GCP and verifies that the user_data provided executes
# $1 - the os/stack to deploy and test
test_user_data() {
   local os_arg=$1
   export TF_VAR_os_arch=$os_arch
   export TF_VAR_namespace=$namespace
   export TF_VAR_subnet=$subnet
   export TF_VAR_network=$network
   local image_family=$2
   cd $os_arg
   echo $image_family
   terraform init -backend-config="bucket=$bucket_name"
   
   if ! terraform apply -auto-approve -var image_family=$image_family; then
      terraform destroy -auto-approve -var image_family=$image_family
      echo 'Terraform Apply Failed!'
      exit 1
   fi

   instance_id=$(terraform output -raw instance_id)
   gcloud compute instances wait $instance_id --zone=$zone --timeout=300
   
   if ! python3 ../test_user_data.py -i $instance_id -o $os_arg; then
      terraform destroy -auto-approve -var image_family=$image_family
      echo 'User data test failed!'
      exit 1
   fi

   terraform destroy -auto-approve -var image_family=$image_family
   cd -
}

# Unzipping ansible files
unzip ansible.zip -d ./ansible

# Determine the appropriate packer file based on OS and image family
if [[ $os_type == "Windows" ]]; then
   PACKER_FILE="gcp_win.pkr.hcl"
elif [[ $image_family == "RHEL_9" || $image_family == "ARM_RHEL_9" ]]; then
   PACKER_FILE="gcp_rhel.pkr.hcl"
else 
   PACKER_FILE="gcp.pkr.hcl"
fi

# Run custom Python script
python3 snow.py

# Initialize and build Packer image
./packer init $PACKER_FILE
./packer build -var "kms_alias=$kms_alias_map" $PACKER_FILE

# Wait for images to be available after build
sleep 30
echo 'Running metadata storage script'
python3 store_metadata.py

# Apply specific configurations for EKS, EMR, or ECS-related images
if [[ $image_family == *"EKS"* || $image_family == *"EMR"* || $image_family == *"ECS"* ]]; then
   cd eks_emr_ecs
   export TF_VAR_image_family=$image_family
   export TF_VAR_statictime="$(date +%H-%M-%S)"
   export TF_VAR_os_arch=$os_arch
   export TF_VAR_namespace=$namespace
   export TF_VAR_network=$network
   export TF_VAR_subnet_1=$subnet_1
   export TF_VAR_subnet_2=$subnet_2
   export TF_VAR_security_group=$security_group
   export TF_VAR_kms_key=$kms_key

   terraform init -backend-config="bucket=$bucket_name"
   
   if ! terraform apply -auto-approve; then
      terraform destroy -auto-approve
      echo 'Terraform Apply Failed!'
      exit 1
   fi

   terraform destroy -auto-approve
   cd -
fi

# Run test_user_data function for non-EKS/EMR/ECS Linux images
if [[ $os_type == "Linux" && $image_family != *"EKS"* && $image_family != *"ECS"* && $image_family != *"EMR"* ]]; then
   test_user_data linux $image_family
fi

# Run test_user_data function for Windows images
if [[ $os_type == "Windows" ]]; then
   test_user_data windows $image_family
fi
