# Define your project IDs
PROJECTS=("project-id-1" "project-id-2")

# Loop through the projects
for project in "${PROJECTS[@]}"; do
  echo "Project: $project"
  
  # List instances and their disk sources
  instances=$(gcloud compute instances list --project="$project" --format="value(name,zone,disks[].source)")

  # Loop through the disk URLs
  for disk_url in $instances; do
    disk_name=$(echo "$disk_url" | awk -F '/' '{print $NF}')
    disk_zone=$(echo "$disk_url" | awk -F '/zones/' '{print $2}' | awk -F '/disks' '{print $1}')

    # Get the source image from the disk
    image_url=$(gcloud compute disks describe "$disk_name" --zone="$disk_zone" --project="$project" --format="value(sourceImage)")

    if [ -n "$image_url" ]; then
      echo "Disk: $disk_name | Image: $image_url"
      
      # Fetch and display labels for the image
      image_name=$(echo "$image_url" | awk -F '/' '{print $NF}')
      image_project=$(echo "$image_url" | awk -F '/' '{print $(NF-3)}') # Fix the project extraction here
      
      gcloud compute images describe "$image_name" --project="$image_project" --format="json(labels)"
    else
      echo "No source image found for disk: $disk_name"
    fi
  done
done
