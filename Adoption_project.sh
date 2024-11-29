# Define your project IDs
PROJECTS=("project-id-1" "project-id-2")

# Loop through the defined projects
for project in "${PROJECTS[@]}"; do
  echo "Project: $project"
  instances=$(gcloud compute instances list --project="$project" --format="value(name,zone,disks[].source)")

  for instance_info in $instances; do
    image_url=$(echo "$instance_info" | awk -F '/' '{print $NF}')
    
    if [[ $image_url == *"images"* ]]; then
      echo "Fetching labels for image: $image_url in project: $project"
      gcloud compute images describe "$image_url" --project="$project" --format="json(labels)"
    fi
  done
done
