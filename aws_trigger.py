
import os
import json
import boto3
import traceback
from image import Image
from datetime import datetime, timezone, timedelta
from loguru import logger

sns = boto3.client('sns')
secrets_client = boto3.client('secretsmanager')
s3 = boto3.client('s3')

sns_topic_name = os.getenv('sns_topic_name', 'sns_topic_name')
response = secrets_client.get_secret_value(SecretId=sns_topic_name)
SNS_TOPIC_ARN = response['SecretString']
 
is_local = os.getenv('is_local', 'is_local')
archive_bucket = os.getenv('archive_bucket', 'archive_bucket')
image_table = os.getenv('image_table', 'image_table')

supported_images_bucket = os.getenv('supported_images_bucket', 'error')
dynamodb_client = boto3.client('dynamodb', region_name='us-east-1')
regional_ec2_clients = {
    'us-east-1': boto3.client('ec2', region_name='us-east-1'),
    'us-east-2': boto3.client('ec2', region_name='us-east-2'),
    'us-west-1': boto3.client('ec2', region_name='us-west-1'),
    'us-west-2': boto3.client('ec2', region_name='us-west-2')
}

# list of valid OS versions
VALID_OS_VERSIONS = {'RHEL_9', 'ARM_RHEL_9', 'Ubuntu_20' , 'Ubuntu_22' , 'ARM_Ubuntu_20' , 'ARM_Ubuntu_22' , 'Amazon_Linux_2', 'ARM_Amazon_Linux_2', 'ECS_Optimized', 'ARM_ECS_Optimized', 'EMR_Optimized', 'ARM_EMR_Optimized','EKS_Optimized_128', 'EKS_Optimized_129', 'ARM_EKS_Optimized_128', 'ARM_EKS_Optimized_129', 'EKS_Optimized_130', 'ARM_EKS_Optimized_130' , 'Windows_2016', 'Windows_2019', 'Windows_2022', 'EBS_Windows_2019', 'AmazonLinux_2023', 'ARM_AmazonLinux_2023',  'ECS_Optimized_2023', 'ARM_ECS_Optimized_2023', 'EMR_7' }
 
def load_supported_amis():
    try:
        # Fetching S3 bucket name from environment variable
        s3_bucket = os.getenv('supported_images_bucket')
        if not s3_bucket:
            raise ValueError("Environment variable 'supported_images_bucket' not set.")
 
        s3_key = 'supported_images.json'
        # Reading the supported_images.json file from S3
        response = s3.get_object(Bucket=s3_bucket, Key=s3_key)
        supported_images_content = response['Body'].read().decode('utf-8')
        supported_images = json.loads(supported_images_content)
        # Create a set of supported OS versions
        supported_os_versions = set()
        for csp, images in supported_images.items():
            supported_os_versions.update(images.keys())
 
        return supported_os_versions
 
    except Exception as e:
        logger.error(f"Failed to load supported AMIs from S3 bucket {s3_bucket}: {e}")
        return None
 
def find_expired_images(oldest, youngest, table, client):
    expired_images = []
    lastKey = 'start'
    params = {
        'TableName': table,
        'KeyConditionExpression': 'csp= :csp',
        'FilterExpression': 'date_created BETWEEN :oldest AND :youngest',
        'ExpressionAttributeValues': {
            ':csp': {'S': 'aws'},
            ':youngest': {'N': str(round(youngest.timestamp()))},
            ':oldest': {'N': str(round(oldest.timestamp()))}
        }
    }
    while lastKey:
        if lastKey and lastKey != 'start':
            params['ExclusiveStartKey'] = lastKey
        response = client.query(**params)
        lastKey = response.get('LastEvaluatedKey', False)
        for item in response.get('Items', []):
            expired_images.append(Image(client, item, 'aws'))
    return expired_images
 
def handle(dynamo, ec2_regional, images=None):
    now = datetime.now(timezone.utc)
    # In ephemeral environments, we archive every image when this is run to keep images from building up
    youngest = (now - timedelta(days=30)) if is_local == "false" else (now - timedelta(days=0))
    oldest = now - timedelta(days=45)
    # If filtered images are provided use them; otherwise, find expired images
    old_images = images if images is not None else find_expired_images(oldest, youngest, image_table, dynamo)
    for image in old_images:
        logger.info(f'Processing image: {image.image_name}')
        for region, client in ec2_regional.items():
            if image.active:
                isarchived, error = image.archiveAWSImage(client, region, archive_bucket)
                if not isarchived:
                    if is_local == "false":
                        message = {
                            'error': str(error),
                            'ami_name': image.image_name,
                            'ami_id': image.regional_image_ids[region]['S']
                        }
                        sns.publish(TopicArn=SNS_TOPIC_ARN, Message=json.dumps(message, indent=2), Subject=f'Archiving of {image.image_name} is Failed')
        if image.active:
            image.deactivate(image_table)
    return {"statusCode": 200}
 
def filter_and_handle(os_version, csp, days_interval=5):
    valid_os_versions = VALID_OS_VERSIONS    
    supported_os_versions = load_supported_amis()

    if supported_os_versions is None:
        logger.error("Failed to load supported OS versions. Aborting archival process.")
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": "Failed to load supported OS versions. Archival process aborted."
            })
        }
    # Validate the provided OS version
    if os_version not in valid_os_versions:
        logger.error(f"Invalid OS version provided: {os_version}")
        return {
            "statusCode": 400,
            "body": json.dumps({
                "error": "Invalid OS version provided.",
                "provided_os_version": os_version,
                "valid_os_versions": list(valid_os_versions)
            })
        }
    # Ensure OS version is not in supported images
    if os_version in supported_os_versions:
        logger.error(f"OS version '{os_version}' is still in use and should not be archived.")
        return {
            "statusCode": 409,
            "body": json.dumps({
                "error": f"OS version '{os_version}' is still in use and should not be archived.",
                "provided_os_version": os_version
            })
        }
 
    now = datetime.now(timezone.utc)
    total_days = 30
    interval_count = total_days // days_interval
 
    for interval in range(interval_count):
        youngest = now - timedelta(days=interval * days_interval)
        oldest = now - timedelta(days=(interval + 1) * days_interval)
        expired_images = find_expired_images(oldest, youngest, image_table, dynamodb_client)
        filtered_images = [img for img in expired_images if img.os_version == os_version]
        logger.info(f"Processing interval {interval + 1}/{interval_count}: {len(filtered_images)} images")
    # Process filtered AMIs
    return handle(dynamodb_client, regional_ec2_clients, filtered_images)
 
def lambda_handler(event, context):
    os_version = event.get('os_version')
    csp = event.get('csp', 'aws')
    if os_version:
        # Use the wrapper function if `os_version` is provided
        return filter_and_handle(os_version, csp)
    else:
        # Use the existing archival flow otherwise
        return handle(dynamodb_client, regional_ec2_clients , None)
