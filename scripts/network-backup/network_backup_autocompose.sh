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

# Access the parameters
if [[ -z "$1" ]]; then
    echo "Error: enclave is empty. Please provide the name of the enclave."
    exit 1
fi
enclave=$1
echo "Enclave: $enclave"
if [[ -z "$1" ]]; then
    echo "Error: kurtosis path is empty. Please provide it."
    exit 1
fi
kurtosis_file_path=$2
echo "Kurtosis file path: $kurtosis_file_path"
network_name="kt-$enclave"

# Check if the network exists
if docker network ls --format '{{.Name}}' | grep -w "$network_name" > /dev/null; then
    echo "Network $network_name exists. Deleting it..."
    docker network rm "$network_name"
else
    echo "Network $network_name does not exist."
fi

# Run kurtosis:
kurtosis run --enclave "$enclave" "$kurtosis_file_path"

# Get the different containers of the environment
containers=$(docker network inspect "$network_name" | jq '[.[0].Containers | to_entries[] | select(.value.Name | contains("kurtosis") | not) | .value.Name] | .[]')

# Stop the enclave
kurtosis enclave stop "$enclave"

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
echo "Saving volume folders..."
for volume in $volumes; do
    echo "Processing volume: $volume"

    # Define the source and target folder paths
    source_folder="/var/lib/docker/volumes/$volume"
    target_folder="/var/lib/docker/volumes/backup_$volume"

    # Check if the source folder exists
    if sudo bash -c "[[ -d \"$source_folder\" ]]"; then
        sudo mv "$source_folder" "$target_folder"
        sudo tar -rvf volume-backups.tar -C /var/lib/docker/volumes "backup_$volume"
    else
        echo "Source folder $source_folder does not exist"
        rm volume-backups.tar
        exit 2
    fi
    sudo mv "$target_folder" "$source_folder"
done

# Remove the enclave
kurtosis enclave rm --force "$enclave"

for quote_container in $containers ; do
    container=${quote_container//\"/}
    base_name=${container%%--*}
    yq -i '.services["'"$base_name"'"] = .services["'"$container"'"] | del(.services["'"$container"'"])' docker-compose.yml
    yq -i '.services["'"$base_name"'"].image = "'"$base_name"':test"' docker-compose.yml

done

mv -f docker-compose.yml ../
sudo chmod 666 volume-backups.tar
mv -f volume-backups.tar ../
