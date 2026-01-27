#!/bin/bash
# Helper functions for Kurtosis operations in snapshot mode

set -euo pipefail

# Get container UUID from service name
# Usage: get_service_uuid <enclave_name> <service_name>
get_service_uuid() {
    local enclave_name="$1"
    local service_name="$2"
    
    kurtosis service inspect "${enclave_name}" "${service_name}" --format '{{ .ContainerID }}' 2>/dev/null || {
        echo "Error: Failed to get UUID for service ${service_name} in enclave ${enclave_name}" >&2
        return 1
    }
}

# Stop a Kurtosis service gracefully
# Usage: stop_service <enclave_name> <service_name>
stop_service() {
    local enclave_name="$1"
    local service_name="$2"
    
    echo "Stopping service ${service_name} in enclave ${enclave_name}..."
    kurtosis service stop "${enclave_name}" "${service_name}" || {
        echo "Error: Failed to stop service ${service_name}" >&2
        return 1
    }
}

# Extract file from container
# Usage: extract_file <enclave_name> <service_name> <src_path> <dest_path>
extract_file() {
    local enclave_name="$1"
    local service_name="$2"
    local src_path="$3"
    local dest_path="$4"

    echo "Extracting ${src_path} from ${service_name} to ${dest_path}..."

    # Create destination directory if it doesn't exist
    mkdir -p "$(dirname "${dest_path}")"

    # Use kurtosis service exec to copy file
    # Note: kurtosis service exec doesn't use --command flag, just pass the command directly
    kurtosis service exec "${enclave_name}" "${service_name}" cat "${src_path}" > "${dest_path}" || {
        echo "Error: Failed to extract file ${src_path} from ${service_name}" >&2
        return 1
    }
}

# Wait for service to reach a specific condition
# Usage: wait_for_service <enclave_name> <service_name> <condition>
# Condition can be: "running", "stopped", "healthy"
wait_for_service() {
    local enclave_name="$1"
    local service_name="$2"
    local condition="$3"
    local max_wait="${4:-60}"  # Default 60 seconds
    local wait_interval="${5:-2}"  # Default 2 seconds
    local elapsed=0
    
    echo "Waiting for service ${service_name} to be ${condition}..."
    
    while [ ${elapsed} -lt ${max_wait} ]; do
        case "${condition}" in
            "running")
                if kurtosis service inspect "${enclave_name}" "${service_name}" --format '{{ .Status }}' 2>/dev/null | grep -q "RUNNING"; then
                    echo "Service ${service_name} is running"
                    return 0
                fi
                ;;
            "stopped")
                if ! kurtosis service inspect "${enclave_name}" "${service_name}" --format '{{ .Status }}' 2>/dev/null | grep -q "RUNNING"; then
                    echo "Service ${service_name} is stopped"
                    return 0
                fi
                ;;
            "healthy")
                # Check if service is healthy (implementation depends on health check mechanism)
                if kurtosis service inspect "${enclave_name}" "${service_name}" --format '{{ .Status }}' 2>/dev/null | grep -q "RUNNING"; then
                    echo "Service ${service_name} appears healthy"
                    return 0
                fi
                ;;
            *)
                echo "Error: Unknown condition '${condition}'" >&2
                return 1
                ;;
        esac
        
        sleep ${wait_interval}
        elapsed=$((elapsed + wait_interval))
    done
    
    echo "Error: Service ${service_name} did not reach condition ${condition} within ${max_wait} seconds" >&2
    return 1
}
