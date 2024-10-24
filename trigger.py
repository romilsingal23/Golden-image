
import json
import logging
import os
from datetime import datetime, timedelta

from azure.mgmt.compute.models import ResourceIdentityType
import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.identity import ClientSecretCredential
import azure.mgmt.compute as compute
from azure.storage.blob import ContainerClient
from azure.mgmt.network import NetworkManagementClient
import azure.keyvault.secrets as secrets
from AzuCoreBuild import build


DYNAMODB_TABLE_NAME = os.getenv('DYNAMODB_TABLE_NAME','DYNAMODB_TABLE_NAME')
RESOURCE_GROUP_NAME = os.getenv('RESOURCE_GROUP_NAME','RESOURCE_GROUP_NAME')
SUBSCRIPTION_ID = os.getenv('SUBSCRIPTION_ID','SUBSCRIPTION_ID')
STORAGE_ACCOUNT_CONTAINER = os.getenv('STORAGE_ACCOUNT_CONTAINER','STORAGE_ACCOUNT_CONTAINER')
STORAGE_ACCOUNT_URL = os.getenv('STORAGE_ACCOUNT_URL','STORAGE_ACCOUNT_URL')
KEY_VAULT_URI = os.getenv('KEY_VAULT_URI', 'KEY_VAULT_URI')
KEY_VAULT_SSH_URI = os.getenv('KEY_VAULT_SSH_URI', 'KEY_VAULT_SSH_URI')
KEY_VAULT_SSH_PUBLIC = os.getenv('KEY_VAULT_SSH_PUBLIC','KEY_VAULT_SSH_PUBLIC')
SUPPORTED_IMAGES_BLOB_NAME = 'supported-images.json'
AZU_CLIENT_ID = os.getenv('AZU_CLIENT_ID', 'AZU_CLIENT_ID')
CLIENT_SECRET = os.getenv('AZU_CLIENT_SECRET', 'AZU_CLIENT_SECRET')
TENANT_ID = os.getenv('AZU_TENANT', 'AZU_TENANT')
IS_LOCAL = os.getenv('is_local', 'is_local')
IS_POC = os.getenv('is_poc', 'true')
IS_PROD = os.getenv('is_prod', 'is_prod')


def main(trigger: func.TimerRequest) -> None:
    credential = ClientSecretCredential(
        client_id=AZU_CLIENT_ID, client_secret=CLIENT_SECRET, tenant_id=TENANT_ID)
    logging.info("configuring clients")
    compute_client = compute.ComputeManagementClient(
        credential, SUBSCRIPTION_ID)
    container_client = ContainerClient(
        account_url=STORAGE_ACCOUNT_URL,
        container_name=STORAGE_ACCOUNT_CONTAINER,
        credential=DefaultAzureCredential())
    network_client = NetworkManagementClient(credential, SUBSCRIPTION_ID)
    secrets_client = secrets.SecretClient(vault_url=KEY_VAULT_SSH_URI,
                                              credential=DefaultAzureCredential())
    public_sshkey = secrets_client.get_secret(KEY_VAULT_SSH_PUBLIC)

    handler(container_client, compute_client, network_client, public_sshkey)


def handler(container_client, compute_client, network_client, public_sshkey):
    exceptions = []
    logging.info('Tenant ID %s', TENANT_ID)
    if IS_POC == "true":
        try:

            # Read blob data
            logging.info('Read supported images blob content')
            supported_images_file = container_client.download_blob(
                SUPPORTED_IMAGES_BLOB_NAME)

            # Convert data to json
            images = json.loads(supported_images_file.readall())
            logging.info('Read supported images blob content - completed')
            result =build.start_build(images, compute_client, network_client, public_sshkey, False)
            
            return result
        except Exception as e:
            logging.error('Error in azu build process \'%s\':', e)
            exceptions.append(e)
            return exceptions
    else:
        logging.info('Not starting the all builds in local and prod environment')
