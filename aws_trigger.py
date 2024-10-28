import os
import json
import boto3, logging
from datetime import datetime, timezone

project_name = os.getenv('project_name', 'project_name')

logger         = logging.getLogger()
logger.setLevel("INFO")

codebuild_client = boto3.client('codebuild', region_name='us-east-1')

s3 = boto3.client('s3')
supported_images_bucket = os.getenv('supported_images_bucket', 'error')

def trigger_build(client, image_name, image):
    start_time = datetime.now(timezone.utc)
    client.start_build(
        projectName = project_name,
        environmentVariablesOverride=[
            {'name': 'image_family', 'value': image_name},
            {'name': 'os_type', 'value': image['os_type']},
            {'name': 'os_owner', 'value': image['owner']},
            {'name': 'os_name', 'value': image['name_filter']},
            {'name': 'os_arch', 'value': image['architecture']},
            {'name': 'os_virtualization', 'value': image['virtualization_type']},
            {'name': 'os_mapping', 'value': image['device_mapping']},
            {'name': 'os_device', 'value': image['device_type']},
            {'name': 'os_root_volume', 'value': image['root_volume']},
            {'name': 'ssh_user', 'value': image['ssh_user']},
            {'name': 'date_created', 'value': datetime.strftime(start_time, '%Y-%m-%d-%H%M%S')}
        ]
    )

def handle(client):
    try:
        #Reading S3 bucket object - supported images json file
        response = s3.get_object(Bucket=supported_images_bucket, Key='supported_images.json')
        file_content = response['Body'].read().decode('utf-8')
    except Exception as e:
        logger.error('Error while reading s3 object. Error - '+str(e))
        return {"statusCode": 500, "error": "Error while reading s3 object."}
    image_list_content = json.loads(file_content)
    image_list = image_list_content['aws']

    for name, image in image_list.items():
        trigger_build(client, name, image)
    return {"statusCode": 200}

def lambda_handler(event, context):
    return handle(codebuild_client)
