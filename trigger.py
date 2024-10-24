import base64
from datetime import datetime, timezone, timedelta
import json
import logging
import os

DYNAMODB_TABLE_NAME = os.getenv('DYNAMODB_TABLE_NAME', 'DYNAMODB_TABLE_NAME')
RESOURCE_GROUP_NAME = os.getenv('RESOURCE_GROUP_NAME', 'RESOURCE_GROUP_NAME')
SUBSCRIPTION_ID = os.getenv('SUBSCRIPTION_ID','SUBSCRIPTION_ID')
NAMESPACE = os.getenv('NAMESPACE', 'NAMESPACE')
STORAGE_ACCOUNT_NAME = os.getenv('STORAGE_ACCOUNT_NAME', 'STORAGE_ACCOUNT_NAME')
KEY_VAULT_URI = os.getenv('KEY_VAULT_URI', 'KEY_VAULT_URI')
KEY_VAULT_IAM_USER_NAME = os.getenv('KEY_VAULT_IAM_USER_NAME', 'KEY_VAULT_IAM_USER_NAME')
KEY_VAULT_IAM_SECRET_NAME = os.getenv('KEY_VAULT_IAM_SECRET_NAME', 'KEY_VAULT_IAM_SECRET_NAME')
GALLERY_NAME = os.getenv('GALLERY_NAME', 'GALLERY_NAME')
PK_VAR_STORAGE_ACCOUNT = os.getenv('PK_VAR_storage_account', 'PK_VAR_storage_account')
AMI_API_ENDPOINT = os.getenv('ami_api_endpoint', 'ami_api_endpoint')
regions = os.getenv('regions', 'regions')
ASK_ID = os.getenv('ASK_ID', 'ASK_ID')
BUILD_IMAGE = os.getenv('BUILD_IMAGE_NAME','BUILD_IMAGE_NAME')
LOCATION = "centralus"
USER_NAME = "azureuser"
managed_identity = os.getenv('managed_identity','managed_identity')
INFRA_NAME = os.getenv('INFRA_NAME','INFRA_NAME')
PROJECT_NAME = os.getenv('PROJECT_NAME', 'PROJECT_NAME')
expire_days = 30
EXCEPTION_STORAGE_ACCOUNT = os.getenv('EXCEPTION_STORAGE_ACCOUNT', 'EXCEPTION_STORAGE_ACCOUNT')
EXCEPTION_GALLERY_NAME = os.getenv('EXCEPTION_GALLERY_NAME', 'EXCEPTION_GALLERY_NAME')
BACKUP_STORAGE_ACCOUNT_URL = os.getenv('BACKUP_STORAGE_ACCOUNT_URL', 'BACKUP_STORAGE_ACCOUNT_URL')
EXP_BACKUP_STORAGE_ACCOUNT_URL = os.getenv('EXP_BACKUP_STORAGE_ACCOUNT_URL', 'EXP_BACKUP_STORAGE_ACCOUNT_URL')
TOPIC_NAME = os.getenv('TOPIC_NAME', 'TOPIC_NAME')


def start_build(images, compute_client, network_client, public_sshkey, isexception):

    for azImage in images['azu']:
        logging.info('azure image %s', azImage)
        if azImage == 'RHEL_8':
            logging.info('not building RHEL 8 image as it is no longer supported')
        else:
            create_build_vm(compute_client, network_client, public_sshkey, isexception, azImage,images, 'latest')
    return True


def create_build_vm(compute_client, network_client, public_sshkey, isexception, azImage,images, image_version):
    if isexception == True :
        Gallery_name=EXCEPTION_GALLERY_NAME
        storage_account=EXCEPTION_STORAGE_ACCOUNT
        backup_storage_account_url = EXP_BACKUP_STORAGE_ACCOUNT_URL
    else:
        Gallery_name=GALLERY_NAME
        storage_account=PK_VAR_STORAGE_ACCOUNT
        backup_storage_account_url = BACKUP_STORAGE_ACCOUNT_URL
    current_date = datetime.now(timezone.utc)
    expire_date = current_date + timedelta(days=expire_days)
    date_created = datetime.strftime(current_date, '%Y-%m-%d-%H%M%S')
    create_date = datetime.strptime(date_created, '%Y-%m-%d-%H%M%S')
    version = datetime.strftime(current_date, '%Y.%m.%d')
    image_name_with_date = azImage + date_created
    VM_NAME = NAMESPACE + 'GIMBuild' + image_name_with_date.replace(
        "_", "").replace("-", "").replace(".", "")
    # Define user data.
    user_data = {
        "SUB_ID": SUBSCRIPTION_ID,
        "namespace": NAMESPACE,
        "gallery_name": Gallery_name,
        "PK_VAR_gallery_resource_group": Gallery_name,
        "account_name": STORAGE_ACCOUNT_NAME,
        "KEY_VAULT_URI": KEY_VAULT_URI,
        "KEY_VAULT_IAM_SECRET_NAME": KEY_VAULT_IAM_SECRET_NAME,
        "KEY_VAULT_IAM_USER_NAME": KEY_VAULT_IAM_USER_NAME,
        "azu_rg_name": RESOURCE_GROUP_NAME,
        "image_family": azImage,
        "image_table": DYNAMODB_TABLE_NAME,
        "PK_VAR_storage_account": storage_account,
        "managed_identity": managed_identity,
        "regions": regions,
        "is_exception": isexception,
        "date_created": date_created,
        "ami_api_endpoint": AMI_API_ENDPOINT,
        "expire_date": datetime.strftime(expire_date, '%Y-%m-%d'),
        "infra_name": INFRA_NAME,
        "image_version": image_version,  # version of Marketplace image we are taking for Golden image building.
        "version": version,   # version of new Golden Image in gallery
        "vm_name": VM_NAME,
        "backup_storage_account_url": backup_storage_account_url,
        "TOPIC_NAME": TOPIC_NAME
    }
    for azImageProperty, azImagePropertyVal in images['azu'][azImage].items():
        if azImageProperty in ('image_offer', 'image_sku', 'os_type', 'image_publisher', 'hyper_v_generation','plan_name', 'plan_product','plan_publisher'):
            user_data[azImageProperty] = azImagePropertyVal
            if azImageProperty == 'os_type':
                user_data["os_version"] = azImagePropertyVal
    # Serializing json
    user_data["capture_name_prefix"]= user_data["image_family"] + str(round(create_date.timestamp()))
    user_data_json = json.dumps(user_data)

    resource_group = virtual_network_name = RESOURCE_GROUP_NAME
    subnet_name = INFRA_NAME
    logging.info('Subnet name %s', subnet_name)

    # Get subnet details through network client
    subnet = network_client.subnets.get(
        resource_group, virtual_network_name, subnet_name)

    logging.info(
        'Subnet info from network_client %s', subnet.id)

    # Create  VM
    logging.info(
        'Creating Virtual Machine for %s code build', azImage)
    logging.info('VM name %s', VM_NAME)
    try:
        nic_id = create_network_interface(
            network_client, azImage, subnet, date_created)
    except Exception as e:
        logging.error(
            'Error in creating network interface %s:', e)
        return False
    vm_parameters = create_vm_parameters(
        nic_id, VM_NAME, user_data_json, public_sshkey, date_created)
    try:
        compute_client.virtual_machines.begin_create_or_update(
            RESOURCE_GROUP_NAME, VM_NAME, vm_parameters)
        logging.info(
            'azure build Temporary VM created successfully..%s', VM_NAME)
        return True
    except Exception as e:
        logging.error(
            'Error in creating VM %s:', e)
        return False
def create_network_interface(network_client, azImage, subnet, date_created):
    # Creting the network interface using the subnet we get from azure
    logging.info('Creating network interface.')
    nic_name = NAMESPACE+azImage+date_created
    nic_params = {
        "location": LOCATION,
        "ip_configurations": [{
            "name": "ipconfig1",
            "subnet": {
                "id": subnet.id
            },
            "private_ip_allocation_method": "Dynamic",
        }],
        "tags": {
            "os_version": azImage,
            "ask_id": ASK_ID,
            "project": "CDTK",
            "date_created": date_created
        }
    }
    poller = network_client.network_interfaces.begin_create_or_update(
        RESOURCE_GROUP_NAME, nic_name, nic_params)
    poller.wait()
    nic = poller.result()
    logging.info(
        'Network Interface created successfully..%s', nic.id)
    return nic.id


def create_vm_parameters(nic_id, vm_name, user_data, ssh_key, date_created):

    # Create the VM parameters structure.
    return {
        "location": LOCATION,
        "tags": {
            "ask_id": ASK_ID,
            "project": PROJECT_NAME,
            "date_created": date_created,
        },
        "identity": {
            "type": "UserAssigned",
            "userAssignedIdentities": {
                managed_identity: {}
            }
        },
        "os_profile": {
            "computer_name": vm_name,
            "admin_username": USER_NAME,
            "linux_configuration": {
                "disable_password_authentication": True,
                "ssh": {
                    "public_keys": [{
                        "path": "/home/{}/.ssh/authorized_keys".format(USER_NAME),
                        "key_data": ssh_key.value
                    }]
                }
            }
        },
        "hardware_profile": {
            "vm_size": "Standard_B2s"
        },
        "storage_profile": {
            "image_reference": {
                # Create VM from golden managed image
                "id": f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP_NAME}/providers/Microsoft.Compute/images/{BUILD_IMAGE}"
            },
            "osDisk": {
                "caching": "ReadWrite",
                "createOption": "FromImage",
                "managedDisk": {"storageAccountType": "Standard_LRS"},
                "name": vm_name,
                "deleteOption": "Delete",
            },
        },
        "userData":  base64.b64encode(bytes(user_data, 'utf-8')).decode("ascii"),
        "network_profile": {
            "network_interfaces": [{
                "id": nic_id,
                "properties": {
                    "deleteOption": "Delete"
                }
            }]
        },
    }
