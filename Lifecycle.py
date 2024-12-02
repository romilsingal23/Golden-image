import os
import json
import boto3
import pytz
from loguru import logger
from google.cloud import compute_v1
from google.cloud import secretmanager
from datetime import datetime, timezone, timedelta


project_id = os.getenv('PROJECT_ID', "zjmqcnnb-gf42-i38m-a28a-y3gmil")  # Google Cloud Project ID
image_family = os.getenv('GIM_FAMILY', "gim-rhel-9")  # Google Cloud image family
image_table =  os.getenv('dynamodb_table', "smadu4-golden-images-metadata")

case_no = 3
delete_interval = 3
deprecate_interval = 1
obsoleted_interval = 2

def get_secret_gcp(secret_id):
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

def update_dynamodb_inactive(db_client, image_name):
    try:
        key = { 'csp': {'S': 'gcp'}, 'image_name': {'S': image_name} }
        db_client.update_item(TableName=image_table, Key=key, 
            UpdateExpression='SET active = :disable',
            ExpressionAttributeValues={ ':disable': {'S': 'false'} } )
        print({'action': 'deactivate', 'item': key})
        return True
    except Exception as e:
        print({'error': str(e)})
        return False

def deprecate_gcp_image(project_id, image_name):
    client = compute_v1.ImagesClient()
    oldest = datetime.now(timezone.utc) - timedelta(days=deprecate_interval)
    filter_str = f"family={image_family} AND status=READY AND name!={image_name}"
    request = compute_v1.ListImagesRequest(project=project_id, filter=filter_str)
    images = client.list(request=request)
    deprecation_status = compute_v1.DeprecationStatus(state="DEPRECATED")
    for image in images:
        try:
            creation_date = datetime.strptime(image.creation_timestamp,"%Y-%m-%dT%H:%M:%S.%f%z")
            creation_date = creation_date.astimezone(pytz.UTC)
            if creation_date < oldest and str(image.deprecated.state) == "":
                client.deprecate(project=project_id, image=image.name
                , deprecation_status_resource=deprecation_status)
                print(f" Deprecated image {image.name}.")
                # break
        except Exception as e:
            logger.error(f"Failed to deprecate image {image.name}: {e}")
            return False, e
    return True, None

def obsolete_gcp_image(project_id):
    client = compute_v1.ImagesClient()
    oldest = datetime.now(timezone.utc) - timedelta(days=obsoleted_interval)
    filter_str = f"deprecated.state=DEPRECATED AND family={image_family}"
    request = compute_v1.ListImagesRequest(project=project_id, filter=filter_str)
    images = client.list(request=request)
    obsoleted_status = compute_v1.DeprecationStatus(state="OBSOLETE")
    aws_access_key = get_secret_gcp(os.getenv('aws_access_key',"aws-access-key"))
    aws_secret_key = get_secret_gcp(os.getenv('aws_secret_key',"aws-secret-key"))
    db_client = boto3.client('dynamodb', region_name='us-east-1'
    , aws_access_key_id=aws_access_key, aws_secret_access_key=aws_secret_key)
    for image in images:
        try:
            creation_date = datetime.strptime(image.creation_timestamp,"%Y-%m-%dT%H:%M:%S.%f%z")
            creation_date = creation_date.astimezone(pytz.UTC)
            if creation_date < oldest:
                client.deprecate(project=project_id, image=image.name
                , deprecation_status_resource=obsoleted_status)
                print(f"Obsoleted image {image.name}.")
                update_dynamodb_inactive(db_client, image.name)
                # break
        except Exception as e:
            logger.error(f"Failed to obsolete image {image.name}: {e}")
            return False, e
    return True, None

def delete_gcp_image(project_id):
    client = compute_v1.ImagesClient()
    oldest = datetime.now(timezone.utc) - timedelta(days=delete_interval)
    filter_str = f"deprecated.state=OBSOLETE AND family={image_family}"
    request = compute_v1.ListImagesRequest(project=project_id, filter=filter_str)
    images = client.list(request=request)
    deleted_status = compute_v1.DeprecationStatus(state="DELETED")
    for image in images:
        try:
            creation_date = datetime.strptime(image.creation_timestamp,"%Y-%m-%dT%H:%M:%S.%f%z")
            creation_date = creation_date.astimezone(pytz.UTC)
            if creation_date < oldest:
                operation = client.delete(project=project_id, image=image.name)
                operation.result()
                print(f"Deleted image {image.name}.")
        except Exception as e:
            logger.error(f"Failed to delete image {image.name}: {e}")
            return False, e
    return True, None


@logger.catch
def main():
    print("Inside main")
    # status, status_msg = obsolete_gcp_image(project_id)
    # status, status_msg = delete_gcp_image(project_id)
    if case_no == 1:
        print("case_no", case_no)
        status, status_msg = deprecate_gcp_image(project_id, 'gim-rhel-9-2024-11-28-092347')
    elif case_no == 2:
        print("case_no", case_no)
        status, status_msg = obsolete_gcp_image(project_id)
    elif case_no == 3:
        print("case_no", case_no)
        status, status_msg = delete_gcp_image(project_id)
    print("status", status)
    print("status_msg", status_msg)

if __name__ == '__main__':
    main()
