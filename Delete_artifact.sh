#!/bin/bash

# Print status message
echo "Fetching packages from Artifact Registry..."

# Fetch the list of Docker images, split by 'gcf-artifacts/' to get everything after it, and store in a variable
IMAGE_NAMES=$(gcloud artifacts docker images list \
  us-east1-docker.pkg.dev/zjmqcnnb-gf42-i38m-a28a-y3gmil/gcf-artifacts \
  --format="value(IMAGE)" | sed 's|.*gcf-artifacts/||')

# Check if no images were found
if [[ -z "$IMAGE_NAMES" ]]; then
  echo "No packages found."
  exit 0
fi

# Process each image name
for IMAGE_NAME in $IMAGE_NAMES; do
  # Check if the image name contains the word "function"
  if [[ "$IMAGE_NAME" == *"function"* ]]; then
    echo "Deleting package: $IMAGE_NAME"
    # Delete the package using the full path
    gcloud artifacts docker images delete \
      "us-east1-docker.pkg.dev/zjmqcnnb-gf42-i38m-a28a-y3gmil/gcf-artifacts/$IMAGE_NAME" --quiet
  else
    echo "Skipping package: $IMAGE_NAME"
  fi
done
