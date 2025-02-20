import os
import sys
import json
import yaml
import boto3
import requests
import traceback
from loguru import logger
from datetime import datetime, timedelta
from google.cloud import compute_v1
from google.cloud import secretmanager
from image_deprecation import deprecate_gcp_image
from email_notification import send_email_notification
 
project_id = os.getenv('PROJECT_ID') 
image_family = os.getenv('GIM_FAMILY')
image_table =  os.getenv('dynamodb_table')
path_to_console = os.getenv('path_to_console')
prisma_base_url = os.getenv('prisma_base_url')
network = os.getenv('NETWORK')
subnetwork = os.getenv('SUBNET')
source_image_family = os.getenv('SOURCE_IMAGE_FAMILY')
source_image_project = os.getenv('SOURCE_IMAGE_PROJECT')
service_account_id = os.getenv('service_account_id')
prisma_username = os.getenv('prisma_username')
prisma_password  = os.getenv('prisma_password')
TOPIC_NAME = os.getenv('TOPIC_NAME')
namespace = os.getenv('namespace')

def get_secret_gcp(secret_id):
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

def get_instance_type(os_version):
    if os_version in ['Windows_2022']:
        return 'n1-standard-2'
    else:
        return 'e2-small'

def get_token(username, secret, auth_endpoint):
    logger.info("fetching the prisma token")
    try:
        payload = json.dumps({ "password": secret, "username": username })
        headers = { 'Content-Type': 'application/json', 'Accept': 'application/json'}
        response = requests.request("POST", auth_endpoint, headers=headers, data=payload)
        prisma_token = response.json()['token']
        return prisma_token, ""
    except Exception as e:
        logger.error(f'error fetching the token: {e}')
        return "", e

def create_secret(secret_id, secret_value):
    try:
        client = secretmanager.SecretManagerServiceClient()
        parent = f"projects/{project_id}"
        name = client.secret_path(project_id, secret_id)
        try:
            client.delete_secret(request={"name": name})
        except:
            print(f"Secret not found. No need to delete.")
 
        secret = client.create_secret(request= { "parent": parent, "secret_id": secret_id
        , "secret": { "replication": { "user_managed": { "replicas": [{"location": 'us-east1'}] }, }
        },  })
        # Add a new version with the secret value
        payload = secret_value.encode("UTF-8")
        parent = client.secret_path(project_id, secret_id)
        response = client.add_secret_version( request={"parent": parent, "payload": {"data": payload}})
    except Exception as e:
        print(f"Error creating secret: {e}")
        return False
    return True
 
def generate_user_data_script(image, prisma_base_url, path_to_console, token):
    response = create_secret('prisma-token', token)
    if image['os_type']['S'] == 'Windows':    
        script = """$bearer=gcloud secrets versions access latest --secret=prisma-token --project="""+f"""{project_id}"""+""";$parameters = @{Uri = '"""+f"""{path_to_console}"""+"""/api/v1/scripts/defender.ps1';Method = "Post";Headers = @{"authorization" = "Bearer $bearer"};OutFile = 'defender.ps1';;};if ($PSEdition -eq 'Desktop') {add-type 'using System.Net;using System.Security.Cryptography.X509Certificates;public class TrustAllCertsPolicy : ICertificatePolicy{public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }}';[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy;} else {$parameters.SkipCertificateCheck = $true;}[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-WebRequest @parameters;.\defender.ps1""" + f""" -type serverWindows -consoleCN {prisma_base_url} -install -u"""
        logger.info("Windows user data script generated successfully.")
        return script
    else:  # for Linux
        script = f"""#!/bin/bash
        bearer_token=$(gcloud secrets versions access latest --secret=prisma-token --project={project_id});curl -sSL -k --header "authorization: Bearer $bearer_token" -X POST {path_to_console}/api/v1/scripts/defender.sh | sudo bash -s -- -c {prisma_base_url} -m --install-host"""
        logger.info("Linux user data script generated successfully.")
        return script

def buildGCPImages(image,prisma_username,prisma_password):
    print("image.os_version", image['os_version'])
    instance_name = image['image_name']['S'] 
    instance_type = get_instance_type(image['os_version'])
    try:
        print("instance_name", instance_name)
        prisma_username = get_secret_gcp(prisma_username)
        prisma_password  = get_secret_gcp(prisma_password)
        url = f"{path_to_console}/api/v33.01/authenticate"
        token, error = get_token(prisma_username,prisma_password,url)
        if error != "":
            return { 'statusCode': 500,
                'headers': { 'Content-Type': 'text/plain' },
                'body': 'Error fetching the token'
            }

        user_data_script = generate_user_data_script(image, prisma_base_url, path_to_console, token)
        zone = 'us-east1-b'
        print("user_data_script created successfully")
        tags = ['ssh-allowed','packer-build']
        windows_metadata = [
            {'key': 'windows-startup-script-ps1', 'value': user_data_script},
            {'key': 'ASKID', 'value': 'AIDE_0077829'},
            {'key': 'Contact', 'value': 'HCC_CDTK@ds.uhc.com'},
            {'key': 'AppName', 'value': 'CDTK Golden Images'},
            {'key': 'CostCenter', 'value': '44770-01508-USAMN022-160465'},
            {'key': 'TemporaryScanImage', 'value': 'True'},
            {'key': 'windows-startup-script-cmd', 'value': 'googet -noconfirm=true update && googet -noconfirm=true install google-compute-engine-ssh'},
            {'key': 'enable-windows-ssh', 'value': 'TRUE'}
        ]

        linux_metadata = [
            {'key': 'startup-script', 'value': user_data_script},
            {'key': 'ASKID', 'value': 'AIDE_0077829'},
            {'key': 'Contact', 'value': 'HCC_CDTK@ds.uhc.com'},
            {'key': 'AppName', 'value': 'CDTK Golden Images'},
            {'key': 'CostCenter', 'value': '44770-01508-USAMN022-160465'},
            {'key': 'TemporaryScanImage', 'value': 'True'}
        ]

        if image['os_type']['S'] == 'Windows':    
            metadata = windows_metadata
            print("Running Windows Metadata")
        else:
            metadata = linux_metadata
            print("Running Linux Metadata")

        labels = {  
             #"os_version" : image["os_version"], ## to add anything in labels
            }
        
        instance_client = compute_v1.InstancesClient()
        disk = compute_v1.AttachedDisk()
        initialize_params = compute_v1.AttachedDiskInitializeParams()
        initialize_params.source_image = f"projects/{project_id}/global/images/family/{image_family}"
        disk.initialize_params = initialize_params
        disk.auto_delete = True
        disk.boot = True
        
        network_interface = compute_v1.NetworkInterface()
        network_interface.network = f"global/networks/{network}"
        network_interface.subnetwork = f"projects/{project_id}/regions/us-east1/subnetworks/{subnetwork}"
        
        instance = compute_v1.Instance()
        instance.name = instance_name
        instance.disks = [disk]
        instance.machine_type = f"zones/{zone}/machineTypes/{instance_type}"
        instance.network_interfaces = [network_interface]
        instance.tags = compute_v1.Tags(items=tags)
        instance.labels = labels
        serviceAccounts= [
            {
            "email": service_account_id.split('/')[-1],
            "scopes": [
                "https://www.googleapis.com/auth/cloud-platform"
            ]
            }
        ]
        instance.service_accounts = serviceAccounts
        instance.metadata = compute_v1.Metadata(items=metadata)
        
        # Create the instance
        operation = instance_client.insert(project=project_id, zone=zone, instance_resource=instance)
        operation.result()  # Wait for the operation to complete
        print("operation.result",operation.result())
        print(f"Instance {instance_name} created successfully.")
    except Exception as e:
        print(f"Instance {instance_name} creation failed. {str(e)}")
        logger.error({'error': str(e), 'traceback': traceback.format_exc()})
        return False
    return True

@logger.catch
def main():
    try:
        print("Inside main")
        aws_access_key = get_secret_gcp(os.getenv('aws_access_key',"aws-access-key"))
        aws_secret_key = get_secret_gcp(os.getenv('aws_secret_key',"aws-secret-key"))
        client = boto3.client('dynamodb', region_name='us-east-1'
        , aws_access_key_id=aws_access_key, aws_secret_access_key=aws_secret_key)
        image_metadata = yaml.load(open('image_metadata.yml'), Loader=yaml.FullLoader)['image_metadata']
        create_time = datetime.strptime(image_metadata['date_created'], "%Y-%m-%d-%H%M%S")
        delete_time = create_time + timedelta(days=365)
        gcp_client = compute_v1.ImagesClient()
        request = compute_v1.GetImageRequest(project=project_id, image=image_metadata['image_name'])
        response = gcp_client.get(request=request)
        source_image_response = gcp_client.get_from_family(project=source_image_project, family=source_image_family)
        
        if response:
            image_id = str(response.id)
            item = {
                'csp': { 'S': 'gcp' },
                'os_version': { 'S': image_metadata['os_version'] },
                'date_created': { 'N': str(round(create_time.timestamp())) },
                'purge_date': { 'N': str(round(delete_time.timestamp())) },
                'os_type': { 'S': image_metadata['os_type'] },
                'image_name': { 'S': image_metadata['image_name'] },
                'checksum': { 'S': image_metadata['checksum'] },
                'src_img_id': { 'S': source_image_response.name},
                'installed_packages': { 'S': image_metadata['installed_packages'] },
                'image_ids': { },
                'active': { 'S': 'true' },
                'is_exception': { 'BOOL': False },
            }
            item['image_ids']['S'] = image_id
            response = client.put_item(TableName=image_table, Item=item)
            print('Successfully wrote back latest build info!')
         
            logger.info(f"namespace: {namespace}")
            if image_id == 'NA':
                email_subject = str(namespace) + " " + image_family + " image build failed"
                body = {'image_version': "Failed"}
                send_email_notification(email_subject, body)
            
            build_status = buildGCPImages(item,prisma_username,prisma_password)
            logger.info(f"Build Status: {build_status}")
            status, status_msg = deprecate_gcp_image(project_id, image_metadata['image_name'])
            logger.info(f"Deprecation Status Message: {status_msg}")
        else:
            logger.error('Failed to find AMI Ids for build!')
            sys.exit(1)
    except Exception as e:
        logger.error(f'Storemetadata build failed!: {e}')
        sys.exit(1)
        
if __name__ == '__main__':
    main()
