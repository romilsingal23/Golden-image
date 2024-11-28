# Get all projects in the organization
for project in $(gcloud projects list --filter="parent.type=organization" --format="value(projectId)"); do
  echo "Project: $project"
  # List all VM instances in each project and their images
  instances=$(gcloud compute instances list --project="$project" --format="value(name,zone,disks[].source)")

  for instance_info in $instances; do
    image_url=$(echo "$instance_info" | awk -F '/' '{print $NF}')
    
    if [[ $image_url == *"images"* ]]; then
      echo "Fetching labels for image: $image_url in project: $project"
      gcloud compute images describe "$image_url" --project="$project" --format="json(labels)"
    fi
  done
done
