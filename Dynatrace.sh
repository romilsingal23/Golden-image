#!/bin/bash
set -e  # Exit if any command fails

# Install required packages
sudo yum install -y wget google-cloud-cli

# Fetch API Token from Google Cloud Secret Manager
API_TOKEN=$(gcloud secrets versions access latest --secret=DYNATRACE_API_TOKEN --format="get(payload.data)" | base64 --decode)

# Download Dynatrace OneAgent installer
wget -O Dynatrace-OneAgent.sh "https://vbk56183.live.dynatrace.com/api/v1/deployment/installer/agent/unix/default/version/1.299.50.20240930-123825?arch=x86&networkZone=gcp.us.east4.nonprod" \
    --header="Authorization: Api-Token $API_TOKEN"

# Make the script executable and run it
chmod +x Dynatrace-OneAgent.sh
/bin/sh Dynatrace-OneAgent.sh --set-monitoring-mode=fullstack \
    --set-app-log-content-access=true \
    --set-network-zone=gcp.us.east4.nonprod \
    --set-host-group=AG_SYN_NONPROD_GCP"

echo "Dynatrace OneAgent installation completed!"
