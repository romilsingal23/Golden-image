#!/bin/bash

# Inputs from Packer post-processor
IMAGE_NAME=$1
PROJECT_ID=$2
KMS_KEY_NAME=$3
LOCATION="global"  # Adjust location if needed

echo "Encrypting image: $IMAGE_NAME in project: $PROJECT_ID with KMS key: $KMS_KEY_NAME"

# Create a new encrypted image
gcloud compute images create "${IMAGE_NAME}-encrypted" \
    --source-image "$IMAGE_NAME" \
    --source-image-project "$PROJECT_ID" \
    --kms-key "projects/$PROJECT_ID/locations/$LOCATION/keyRings/<KEY_RING_NAME>/cryptoKeys/$KMS_KEY_NAME"

if [ $? -eq 0 ]; then
    echo "Image $IMAGE_NAME successfully encrypted to ${IMAGE_NAME}-encrypted."
else
    echo "Failed to encrypt the image $IMAGE_NAME."
    exit 1
fi
