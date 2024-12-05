#!/bin/bash

# Print status message
echo "Fetching packages from Artifact Registry..."

# Fetch the list of Docker images, split by 'gcf-artifacts/' to get everything after it, and store in a file
gcloud artifacts docker images list \
  us-east1-docker.pkg.dev/zjmqcnnb-gf42-i38m-a28a-y3gmi/gcf-artifacts \
  --format="value(IMAGE)" | sed 's|.*gcf-artifacts/||' > package_list.txt

# Check if the file is empty
if [[ ! -s package_list.txt ]]; then
  echo "No packages found."
  exit 0
fi

# Process each line from the file
while IFS= read -r IMAGE_NAME; do
  # Check if the image name contains the word "function"
  if [[ "$IMAGE_NAME" == *"function"* ]]; then
    echo "Deleting package: $IMAGE_NAME"
    # Delete the package using the full path from the original list
    gcloud artifacts docker images delete \
      "us-east1-docker.pkg.dev/zjmqcnnb-gf42-i38m-a28a-y3gmi/gcf-artifacts/$IMAGE_NAME" --quiet
  else
    echo "Skipping package: $IMAGE_NAME"
  fi
done < package_list.txt

# Clean up: Remove the file after processing
rm -f package_list.txt
