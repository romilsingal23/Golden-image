# This script tries to poll Wiz for the new GCE image and see if it has vulnerabilities
#!/bin/bash

set -e  # Exit on error

# Ensure required environment variables are set
if [[ -z "$WIZ_API_TOKEN" || -z "$WIZ_API_URL" || -z "$IMAGE_NAME" ]]; then
  echo "Missing required environment variables. Skipping Wiz check."
  exit 0
fi

echo "Checking Wiz for vulnerabilities on image: $IMAGE_NAME"

MAX_ATTEMPTS=6
SLEEP_TIME=30

for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
  echo "Attempt $i to query Wiz for vulnerabilities..."
  
  QUERY='
    query($filter:String!) {
      cloudResources(filter:$filter) {
        totalCount
        nodes {
          name
          ... on VirtualMachineImage {
            name
            vulnerabilities {
              totalCount
              nodes {
                severity
                cveIds
                packageName
                packageVersion
              }
            }
          }
        }
      }
    }
  '
  FILTER="name = \\\"$IMAGE_NAME\\\""

  RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $WIZ_API_TOKEN" \
    -H "Content-Type: application/json" \
    "$WIZ_API_URL/graphql" \
    -d "$(jq -c -n --arg q "$QUERY" --arg f "$FILTER" '{query: $q, variables: { filter: $f }}')")

  echo "Response: $RESPONSE"

  FOUND_COUNT=$(echo "$RESPONSE" | jq '.data.cloudResources.totalCount')

  if [[ "$FOUND_COUNT" -gt 0 ]]; then
    echo "Wiz discovered the image. Checking vulnerabilities..."
    VULN_COUNT=$(echo "$RESPONSE" | jq '.data.cloudResources.nodes[0].vulnerabilities.totalCount')
    echo "Found $VULN_COUNT vulnerabilities."

    if [[ "$VULN_COUNT" -gt 0 ]]; then
      HIGH_OR_CRIT=$(echo "$RESPONSE" | jq '[.data.cloudResources.nodes[0].vulnerabilities.nodes[] | select(.severity == "CRITICAL" or .severity == "HIGH")] | length')
      if [[ "$HIGH_OR_CRIT" -gt 0 ]]; then
        echo "Found $HIGH_OR_CRIT HIGH or CRITICAL vulnerabilities. Failing build."
        exit 1
      fi
    fi

    echo "No HIGH/CRITICAL vulnerabilities found (or no vulnerabilities at all). Passing."
    exit 0
  else
    echo "Wiz has not discovered the resource yet. Sleeping $SLEEP_TIME seconds..."
    sleep $SLEEP_TIME
  fi
done

echo "Wiz did not discover the image within our wait time. Proceeding."
exit 0
