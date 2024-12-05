#!/bin/bash

# Print status message
echo "Fetching packages from Artifact Registry..."

# Fetch the list of Docker images and store in a file with proper formatting
gcloud artifacts docker images list \
  us-east1-docker.pkg.dev/zjmqcnnb-gf42-i38m-a28a-y3gmi/gcf-artifacts \
  --format="value(IMAGE)" | tr -d '\n' | tr ' ' '\n' > package_list.txt

# Check if the file is empty
if [[ ! -s package_list.txt ]]; then
  echo "No packages found."
  exit 0
fi

# Process each package or image from the file
while IFS= read -r line; do
  # Check if the line contains the word "function"
  if [[ "$line" == *"function"* ]]; then
    echo "Deleting package: $line"
    # Delete the package
    gcloud artifacts docker images delete "$line" --quiet
  else
    echo "Skipping package: $line"
  fi
done < package_list.txt

# Clean up: Remove the file after processing
rm -f package_list.txt
