#!/bin/bash

PROJECT_ID=$1
LOCATION=$2
REPOSITORY=$3

echo "Fetching packages from Artifact Registry..."
PACKAGES=$(gcloud artifacts packages list \
  --project="${PROJECT_ID}" \
  --location="${LOCATION}" \
  --repository="${REPOSITORY}" \
  --format="value(name)")

if [[ -z "$PACKAGES" ]]; then
  echo "No packages found."
  exit 0
fi

for PACKAGE in $PACKAGES; do
  if [[ "$PACKAGE" == *"function"* ]]; then
    echo "Deleting package: $PACKAGE"
    gcloud artifacts packages delete "$PACKAGE" \
      --project="${PROJECT_ID}" \
      --location="${LOCATION}" \
      --quiet
  fi
done
