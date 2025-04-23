#!/bin/bash

# Check if the dependencies are installed
if command -v yq >/dev/null 2>&1; then
    echo "yq is installed"
else
    echo "yq is not installed"
    exit 1
fi
if command -v poetry >/dev/null 2>&1; then
    echo "poetry is installed"
else
    echo "poetry is not installed"
    exit 1
fi

# Run kurtosis:
kurtosis run --enclave cdk github.com/0xPolygon/kurtosis-cdk

# Get the different containers of the environment
containers=$(docker network inspect kt-cdk | jq '[.[0].Containers | to_entries[] | select(.value.Name | contains("kurtosis") | not) | .value.Name] | .[]')

# Stop the enclave
kurtosis enclave stop cdk

# Create the container copies
for quote_container in $containers ; do
    container=${quote_container//\"/}
    base_name=${container%%--*}
    # shellcheck disable=SC2086
    docker container commit $container $base_name:test
done

# Check docker-autocompose folder
if [[ ! -d "./docker-autocompose" ]]; then
    echo "docker-autocompose folder not found. Cloning the repo..."
    git clone git@github.com:Red5d/docker-autocompose.git
    cd docker-autocompose || exit 99
    poetry install
else
    echo "docker-autocompose folder found"
    cd docker-autocompose || exit 99
fi

# Create docker compose file
container_list=""
# Loop through the containers and dynamically build the list
for quote_container in $containers; do
    container=${quote_container//\"/}
    container_list="$container_list $container"
done
# Run the autocompose command with the dynamically built container list
# shellcheck disable=SC2086
poetry run autocompose $container_list > docker-compose.yml

volumes=$(yq '.volumes | keys' docker-compose.yml | sed 's/^- //')
echo "Renaming volume folders..."
for volume in $volumes; do
    echo "Processing volume: $volume"

    # Define the source and target folder paths
    source_folder="/var/lib/docker/volumes/$volume"
    target_folder="/var/lib/docker/volumes/backup_$volume"

    # Check if the source folder exists
    if sudo bash -c "[[ -d \"$source_folder\" ]]"; then
        sudo mv "$source_folder" "$target_folder"
    else
        echo "Source folder $source_folder does not exist"
        exit 2
    fi
done

# Remove the enclave
kurtosis enclave rm --force cdk

# Restore docker volumes and create new volumes with that data:
sudo bash -c 'for dir in /var/lib/docker/volumes/backup_*/; do 
    new_name="$(basename "$dir" | sed "s/^backup_//")"; 
    mv "$dir" "$(dirname "$dir")/$new_name"; 
    docker volume create "$new_name"; 
  done'

# Recreate the docker network
docker network create kt-cdk

for quote_container in $containers ; do
    container=${quote_container//\"/}
    base_name=${container%%--*}
    yq -i '.services["'"$base_name"'"] = .services["'"$container"'"] | del(.services["'"$container"'"])' docker-compose.yml
    yq -i '.services["'"$base_name"'"].image = "'"$base_name"':test"' docker-compose.yml

done