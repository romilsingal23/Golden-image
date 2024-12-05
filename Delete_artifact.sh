#!/bin/bash

# Print status message
echo "Fetching packages from Artifact Registry..."

# Fetch the list of Docker images and store in a file
gcloud artifacts docker images list \
  us-east1-docker.pkg.dev/zjmqcnnb-gf42-i38m-a28a-y3gmil/gcf-artifacts \
  --format="value(IMAGE)" > package_list.txt

# Check if the file is empty
if [[ ! -s package_list.txt ]]; then
  echo "No packages found."
  exit 0
fi

# Process each line directly
while IFS= read -r; do
  # Check if the line contains the word "function"
  if [[ $REPLY == *"function"* ]]; then
    echo "Deleting package: $REPLY"
    # Delete the package
    gcloud artifacts docker images delete "$REPLY" --quiet
  else
    echo "Skipping package: $REPLY"
  fi
done < package_list.txt

# Clean up: Remove the file after processing
rm -f package_list.txt
