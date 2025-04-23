#!/bin/bash

enclave=$1
tar_file=$2

# Restore docker volumes and create new volumes with that data
sudo tar -xvf "$tar_file" -C /var/lib/docker/volumes/

sudo bash -c 'for dir in /var/lib/docker/volumes/backup_*/; do 
    new_name="$(basename "$dir" | sed "s/^backup_//")"; 
    mv "$dir" "$(dirname "$dir")/$new_name"; 
    docker volume create "$new_name"; 
  done'

# Recreate the docker network
docker network create "kt-$enclave"

# Run docker compose. Make sure the different container are running in the right order.
# docker compose -f docker-compose.yml up -d