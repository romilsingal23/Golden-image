same error if impersonate service account



$ LATEST_IMAGE=$(gcloud compute images describe-from-family rsingal-gim-rhel-9 --format="value(name)")   



#gcloud compute images create "${LATEST_IMAGE}-encrypted"   --source-image "$LATEST_IMAGE"   --kms-key projects/zjmqcnnb-gf42-i38m-a28a-y3gmil/locations/us-east1/keyRings/rsingal-key-ring/cryptoKeys/rsingal_key --impersonate-service-account=rsingal-cloud-build-sa@zjmqcnnb-gf42-i38m-a28a-y3gmil.iam.gserviceaccount.com

gal-cloud-build-sa@zjmqcnnb-gf42-i38m-a28a-y3gmil.iam.gserviceaccount.com;58456cf6-01d0-418e-a1bf-27fd831f826eWARNING: This command is using service account impersonation. All API calls will be executed as [rsingal-c

loud-build-sa@zjmqcnnb-gf42-i38m-a28a-y3gmil.iam.gserviceaccount.com].

WARNING: This command is using service account impersonation. All API calls will be executed as [rsingal-cloud-build-sa@zjmqcnnb-gf42-i38m-a28a-y3gmil.iam.gserviceaccount.com].

ERROR: (gcloud.compute.images.create) Could not fetch resource:

 - Cloud KMS error when using key projects/zjmqcnnb-gf42-i38m-a28a-y3gmil/locations/us-east1/keyRings/rsingal-key-ring/cryptoKeys/rsingal_key: Permission 'cloudkms.cryptoKeyVersions.useToEncrypt' denied on resource 'projects/zjmqcnnb-gf42-i38m-a28a-y3gmil/locations/us-east1/keyRings/rsingal-key-ring/cryptoKeys/rsingal_key' (or it may not exist).



# gcloud kms keys list --location us-east1 --keyring rsingal-key-ring

NAME

  PURPOSE     ALGORITHM          PROTECTION_LEVEL LABELS              PRIMARY_ID PRIMARY_STATE

projects/zjmqcnnb-gf42-i38m-a28a-y3gmil/locations/us-east1/keyRings/rsingal-key-ring/cryptoKeys/rsingal_key ENCRYPT_DECRYPT GOOGLE_SYMMETRIC_ENCRYPTION SOFTWARE     goog-terraform-provisioned=true 1   

   ENABLED



$ gcloud kms keys get-iam-policy rsingal_key --keyring=rsingal-key-ring --location=us-east1

bindings:

- members:

 - serviceAccount:rsingal-cloud-build-sa@zjmqcnnb-gf42-i38m-a28a-y3gmil.iam.gserviceaccount.com

 role: roles/cloudkms.cryptoKeyEncrypterDecrypter

etag: BwYogNGhVxk=

version: 1

