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
 
project_id = os.getenv('PROJECT_ID', "zjmqcnnb-gf42-i38m-a28a-y3gmil")  # Google Cloud Project ID
image_family = os.getenv('GIM_FAMILY', "gim-rhel-9")  # Google Cloud image family
image_table =  os.getenv('dynamodb_table', "smadu4-golden-images-metadata")
path_to_console = os.getenv('path_to_console', 'https://us-east1.cloud.twistlock.com/us-1-111573393')
prisma_base_url = os.getenv('prisma_base_url', 'us-east1.cloud.twistlock.com')
network = os.getenv('NETWORK')
subnetwork = os.getenv('SUBNET')
#network = 'rsingal-gcp-build-network'
#subnetwork = 'rsingal-gcp-build-subnet'

prisma_username = os.getenv('prisma_username','prisma-username')
prisma_password  = os.getenv('prisma_password','prisma-password')

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
            print(f"Secret {secret_id} not found. No need to delete.")
 
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
    print("response", response)
    if image['os_type'] == 'Windows':
        script = """<powershell>
        $bearer = gcloud secrets versions access latest --secret=prisma-token --project="""+f"""{project_id}"""+"""
        $parameters = @{
            Uri = '"""+f"""{path_to_console}"""+"""/api/v1/scripts/defender.ps1';
            Method = "Post";
            Headers = @{"authorization" = "Bearer $bearer"};
            OutFile = 'defender.ps1';;
        };
        if ($PSEdition -eq 'Desktop') {
            add-type 'using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCertsPolicy : ICertificatePolicy{
              public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }
            }';
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy;
        } else {
            $parameters.SkipCertificateCheck = $true;
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
        Invoke-WebRequest @parameters;.\defender.ps1""" + f""" -type serverWindows -consoleCN {prisma_base_url} -install -u
        </powershell>"""
        logger.info("Windows user data script generated successfully.")
        return script
    else:  # for Linux
        script = f"""#!/bin/bash
        bearer_token=$(gcloud secrets versions access latest --secret=prisma-token --project={project_id});curl -sSL -k --header "authorization: Bearer $bearer_token" -X POST {path_to_console}/api/v1/scripts/defender.sh | sudo bash -s -- -c {prisma_base_url} -m --install-host"""
        logger.info("Linux user data script generated successfully.")
        return script

def buildGCPImages(image,prisma_username,prisma_password):
    print("image.os_version", image['os_version'])
    instance_name = image['image_name']['S'] #.replace("_", "").replace("-", "").replace(".", "")
    instance_type = get_instance_type(image['os_version'])
    try:
        print("image", image)
        
        print("instance_name", instance_name)
        print("instance_type", instance_type)
        prisma_username = get_secret_gcp(prisma_username)
        prisma_password  = get_secret_gcp(prisma_password)
        print("prisma_username", prisma_username)
        print("prisma_password", prisma_password)
        print("prisma_base_url", prisma_base_url)
        print("path_to_console", path_to_console)
        
        url = f"{path_to_console}/api/v33.01/authenticate"
        token, error = get_token(prisma_username,prisma_password,url)
        print("token created successfully", token)
        if error != "":
            return { 'statusCode': 500,
                'headers': { 'Content-Type': 'text/plain' },
                'body': 'Error fetching the token'
            }

        user_data_script = generate_user_data_script(image, prisma_base_url, path_to_console, token)
        zone = 'us-east1-b'
        print("user_data_script created successfully",user_data_script)
        tags = ['ssh-allowed']
        metadata = [
            {'key': 'startup-script', 'value': user_data_script}
        ]
        labels = {  #Name  = f'GoldenImageScan-{image["os_version"]}',
             #"SourceImage" : image["image_name"],
             #"os_version" : image["os_version"],
             #"date_created" : str(image["date_created"]),
             #"contact":  "HCC_CDTK@ds.uhc.com",
             #"appname": "CDTK Golden Images",
             #"costcenter": "44770-01508-USAMN022-160465",
             #"askid" : "AIDE_0077829",
             "temporaryscanimage" : "true"
            }
            # # {'key': 'Name', 'value': f'GoldenImageScan-{image['os_version']}'},
            # {'key': 'SourceImage', 'value': image['image_name']},
            # {'key': 'os_version', 'value': image['os_version']},
            # #{'key': 'date_created', 'value': str(image['date_created'])},
            # {'key': 'Contact', 'value': 'HCC_CDTK@ds.uhc.com'},
            # {'key': 'AppName', 'value': 'CDTK Golden Images'},
            # {'key': 'CostCenter', 'value': '44770-01508-USAMN022-160465'},
            # {'key': 'ASKID', 'value': 'AIDE_0077829'},
            # {'key': 'TemporaryScanImage', 'value': 'True'}
            # ]
        
        instance_client = compute_v1.InstancesClient()
        disk = compute_v1.AttachedDisk()
        initialize_params = compute_v1.AttachedDiskInitializeParams()
        initialize_params.source_image = f"projects/{project_id}/global/images/family/{image_family}"
        disk.initialize_params = initialize_params
        disk.auto_delete = True
        disk.boot = True
        print("token2", project_id)
        
        network_interface = compute_v1.NetworkInterface()
        network_interface.network = f"global/networks/{network}"
        network_interface.subnetwork = f"projects/{project_id}/regions/us-east1/subnetworks/{subnetwork}"
        print("token3",network)
        
        instance = compute_v1.Instance()
        #instance.name = "prisma-rhel-instance"
        instance.name = instance_name
        instance.disks = [disk]
        instance.machine_type = f"zones/{zone}/machineTypes/{instance_type}"
        instance.network_interfaces = [network_interface]
        instance.tags = compute_v1.Tags(items=tags)
        instance.labels = labels
        serviceAccounts= [
            {
            "email": "rsingal-cloud-build-sa@zjmqcnnb-gf42-i38m-a28a-y3gmil.iam.gserviceaccount.com",
            "scopes": [
                "https://www.googleapis.com/auth/cloud-platform"
            ]
            }
        ]
        instance.service_accounts = serviceAccounts
        #instance.metadata = compute_v1.Metadata(items=metadata + [{'key': 'startup-script', 'value': user_data_script}])
        instance.metadata = compute_v1.Metadata(items=metadata)
        print("token4",subnetwork)
        
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
    print("Inside main")
    aws_access_key = get_secret_gcp(os.getenv('aws_access_key',"aws-access-key"))
    aws_secret_key = get_secret_gcp(os.getenv('aws_secret_key',"aws-secret-key"))
    client = boto3.client('dynamodb', region_name='us-east-1'
    , aws_access_key_id=aws_access_key, aws_secret_access_key=aws_secret_key)
    image_metadata = yaml.load(open('image_metadata.yml'), Loader=yaml.FullLoader)['image_metadata']
    create_time = datetime.strptime(image_metadata['date_created'], "%Y-%m-%d-%H%M%S")
    delete_time = create_time + timedelta(days=365)
    gcp_client = compute_v1.ImagesClient()
    response = gcp_client.get_from_family(project=project_id, family=image_family)
    print("response of id is:", response.id)
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
            # 'src_img_id': { 'S': image_metadata['src_img_id'] },
            'installed_packages': { 'S': image_metadata['installed_packages'] },
            'image_ids': { },
            'active': { 'S': 'true' },
            'is_exception': { 'BOOL': False },
        }
        item['image_ids']['S'] = image_id
        response = client.put_item(TableName=image_table, Item=item)
        print('Successfully wrote back latest build info!')
        return buildGCPImages(item,prisma_username,prisma_password)
    else:
        logger.error('Failed to find AMI Ids for build!')
        sys.exit(1)

if __name__ == '__main__':
    main()
