#!/bin/bash

# Print status message
echo "Fetching packages from Artifact Registry..."

# Fetch the list of Docker images and store in a file
gcloud artifacts docker images list \
  us-east1-docker.pkg.dev/zjmqcnnb-gf42-i38m-a28a-y3gmi/gcf-artifacts \
  --format="value(IMAGE)" > package_list.txt

# Check if the file is empty
if [[ ! -s package_list.txt ]]; then
  echo "No packages found."
  exit 0
fi

# Iterate through each line in the file
while IFS= read -r PACKAGE; do
  # Check if the package name contains the word "function"
  if [[ "$PACKAGE" == *"function"* ]]; then
    echo "Deleting package: $PACKAGE"
    # Delete the package
    gcloud artifacts docker images delete "$PACKAGE" --quiet
  else
    echo "Skipping package: $PACKAGE"
  fi
done < package_list.txt

# Clean up: Remove the file after processing
rm -f package_list.txt
