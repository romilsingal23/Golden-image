#!/bin/bash

# Define your service account email and Python script path
SERVICE_ACCOUNT_EMAIL="<SERVICE_ACCOUNT_EMAIL>"
PYTHON_SCRIPT_PATH="your_script.py"

# Impersonate the service account and get the access token
ACCESS_TOKEN=$(gcloud auth application-default print-access-token --impersonate-service-account=$SERVICE_ACCOUNT_EMAIL)

# Check if the access token was successfully retrieved
if [ -z "$ACCESS_TOKEN" ]; then
  echo "Failed to retrieve access token"
  exit 1
fi

# Set the access token as an environment variable
export GOOGLE_CLOUD_ACCESS_TOKEN=$ACCESS_TOKEN

# Run the Python script
python $PYTHON_SCRIPT_PATH
