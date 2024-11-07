import os
import boto3
from loguru import logger
from azure.identity import ClientSecretCredential
from azure.storage.blob import ContainerClient
STORAGE_ACCOUNT_URL = os.getenv('STORAGE_ACCOUNT_URL')
Client_id=os.getenv('client_id')
Client_secret=os.getenv('client_secret')
Tenant_id=os.getenv('tenant_id')

def handler():
    STORAGE_ACCOUNT_CONTAINER = 'snow-agent'
    ssmClient = boto3.client('ssm')
    client_id=ssmClient.get_parameter(Name=Client_id, WithDecryption=True)['Parameter']['Value']
    client_secret=ssmClient.get_parameter(Name=Client_secret, WithDecryption=True)['Parameter']['Value']
    tenant_id=ssmClient.get_parameter(Name=Tenant_id, WithDecryption=True)['Parameter']['Value']
    logger.info(f"Client ID: {client_id}")
    logger.info(f"Tenant ID: {tenant_id}")    
    credential = ClientSecretCredential(
        client_id=client_id,
        client_secret=client_secret,
        tenant_id=tenant_id
    )
    logger.info("Downloading blobs...")
    try:
        container_client = ContainerClient(
            account_url=STORAGE_ACCOUNT_URL,
            container_name=STORAGE_ACCOUNT_CONTAINER,
            credential=credential)
        blobs = container_client.list_blobs()
        logger.info("Listing blobs...")
        for blob in blobs:
            logger.info(blob.name)
            path=os.path.join("/tmp", blob.name)
            with open(path, "wb") as f:
                download_stream = container_client.download_blob(blob)
                f.write(download_stream.readall())
    except Exception as e:
        logger.info("Failed to download the blobs")
        logger.error(e)
        raise e

if __name__ == '__main__':
    handler()
