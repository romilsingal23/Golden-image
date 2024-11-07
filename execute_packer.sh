#!/bin/bash
set -e

# Deploys an ami and verifies that the user_data provided executes
# $1 - the os/stack to deploy and test
test_user_data() {
   local os_arg=$1
   export TF_VAR_os_arch=$os_arch
   export TF_VAR_namespace=$namespace
   export TF_VAR_subnet_id=$eks_subnet_1
   export TF_VAR_security_group_id=$security_group_id
   local image_family=$2
   cd $os_arg
   echo $image_family
   terraform init -backend-config="bucket=$bucket_name"
   if ! terraform apply -auto-approve -var image_family=$image_family; then
      terraform destroy -auto-approve -var image_family=$image_family
      echo 'Terraform Apply Failed!'
      crash
   fi

   instance_id=`terraform output -raw instance_id` 
   aws ec2 wait instance-running --instance-ids $instance_id
   if ! python3 ../test_user_data.py -i $instance_id -o $os_arg; then
      terraform destroy -auto-approve -var image_family=$image_family
      echo 'User data test failed!'
      crash
   fi
   terraform destroy -auto-approve -var image_family=$image_family
   cd -
}

unzip ansible.zip -d ./ansible

if [[ $os_type == "Windows" ]]
then
   PACKER_FILE="aws_win.pkr.hcl"
elif [[ $image_family == "RHEL_9" ||  $image_family == "ARM_RHEL_9" ]]
then
   PACKER_FILE="aws_rhel.pkr.hcl"
else 
   PACKER_FILE="aws.pkr.hcl"
fi
python3 snow.py

./packer init $PACKER_FILE
./packer build -var $kms_alias_map $PACKER_FILE

sleep 30 # wait a bit as there can be some timing issues before the amis can be queried
echo 'store_metadata.py'
python3 store_metadata.py

if [[ $image_family == *"EKS"* || $image_family == *"EMR"* || $image_family == *"ECS"* ]]
then
   cd eks_emr_ecs
   export TF_VAR_image_family=$image_family
   export TF_VAR_statictime="$(date +%H-%M-%S)"
   export TF_VAR_os_arch=$os_arch
   export TF_VAR_namespace=$namespace
   export TF_VAR_vpc_id=$vpc_id
   export TF_VAR_subnet_1=$eks_subnet_1
   export TF_VAR_subnet_2=$eks_subnet_2
   export TF_VAR_security_group=$security_group_id
   export TF_VAR_emr_service_security_group=$emr_service_security_group_id
   export TF_VAR_emr_master_security_group=$emr_master_security_group_id
   export TF_VAR_emr_kms_key=$emr_kms_key
   terraform init -backend-config="bucket=$bucket_name"
   if ! terraform apply -auto-approve; then
      terraform destroy -auto-approve
      echo 'Terraform Apply Failed!'
      crash
   fi
   terraform destroy -auto-approve
   cd -
fi

if [[ $os_type == "Linux" && $image_family != *"EKS"* && $image_family != *"ECS"* && $image_family != *"EMR"* ]]
then
   test_user_data linux $image_family
fi

if [[ $os_type == "Windows" ]]
then
   test_user_data windows $image_family
fi
