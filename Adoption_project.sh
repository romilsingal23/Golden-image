l# Define your project IDs
PROJECTS=("project-id-1" "project-id-2")

# Loop through the projects
for project in "${PROJECTS[@]}"; do
  echo "Project: $project"

  # List instances and their associated disk sources
  instances=$(gcloud compute instances list --project="$project" --format="json" | jq -r '.[] | .name + "," + .zone + "," + (.disks[].source // "")')

  # Loop through the instance disks
  while IFS=',' read -r instance_name zone disk_url; do
    if [ -z "$disk_url" ]; then
      echo "No disks found for instance: $instance_name in zone: $zone"
      continue
    fi

    disk_name=$(echo "$disk_url" | awk -F '/' '{print $NF}')
    disk_zone=$(echo "$disk_url" | awk -F '/zones/' '{print $2}' | awk -F '/disks' '{print $1}')

    # Get the source image from the disk
    image_url=$(gcloud compute disks describe "$disk_name" --zone="$disk_zone" --project="$project" --format="value(sourceImage)")

    if [ -n "$image_url" ]; then
      echo "Disk: $disk_name | Image: $image_url"

      # Extract the image name and project from the image URL
      image_name=$(echo "$image_url" | awk -F '/' '{print $NF}')
      image_project=$(echo "$image_url" | awk -F '/' '{print $(NF-3)}')

      # Fetch and display the labels for the image
      gcloud compute images describe "$image_name" --project="$image_project" --format="json(labels)" | jq .
    else
      echo "No source image found for disk: $disk_name"
    fi
  done <<< "$instances"
done
