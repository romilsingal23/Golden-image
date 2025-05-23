#!/bin/bash

PROJECT_ID="$1" # Input from null resource in terraform code

# Print status message
echo "Fetching Docker images from Artifact Registry..."

# Fetch the list of Docker images, split by 'gcf-artifacts/' to get everything after it, and store in a variable
IMAGE_LIST=$(gcloud artifacts docker images list \
  us-east1-docker.pkg.dev/$PROJECT_ID/gcf-artifacts \
  --format="value(IMAGE)" | sed 's|.*gcf-artifacts/||' | sort | uniq)

# Check if no images were found
if [[ -z "$IMAGE_LIST" ]]; then
  echo "No Docker images found in the registry."
  exit 0
fi

# Process each unique image name
for IMAGE_NAME in $IMAGE_LIST; do
  # Check if the image name contains the word "function"
  if [[ "$IMAGE_NAME" == *"function"* ]]; then
    echo "Deleting package: $IMAGE_NAME"
    # Delete the package using the full path
    gcloud artifacts docker images delete \
      "us-east1-docker.pkg.dev/$PROJECT_ID/gcf-artifacts/$IMAGE_NAME" --quiet
  else
    echo "Skipping package: $IMAGE_NAME"
  fi
done
