#!/bin/bash
# Helper functions for building L1 Docker images in snapshot mode

set -euo pipefail

# Replace template variables in a file
# Usage: replace_template_vars <template_file> <output_file> <var1=value1> [var2=value2] ...
replace_template_vars() {
    local template_file="$1"
    local output_file="$2"
    shift 2
    
    # Start with template file
    cp "${template_file}" "${output_file}"
    
    # Replace each variable
    while [ $# -gt 0 ]; do
        local var_value="$1"
        local var_name="${var_value%%=*}"
        local var_val="${var_value#*=}"
        
        # Replace {{VAR_NAME}} with value
        sed -i "s|{{${var_name}}}|${var_val}|g" "${output_file}"
        
        shift
    done
}

# Generate JWT secret if it doesn't exist
# Usage: ensure_jwt_secret <datadir_path>
ensure_jwt_secret() {
    local datadir_path="$1"
    local jwt_secret_path="${datadir_path}/jwtsecret"
    
    if [ ! -f "${jwt_secret_path}" ]; then
        echo "Generating JWT secret at ${jwt_secret_path}..."
        
        # Generate 32-byte hex string
        if command -v openssl &> /dev/null; then
            openssl rand -hex 32 | tr -d '\n' > "${jwt_secret_path}"
        elif command -v shuf &> /dev/null; then
            # Fallback: generate random hex using shuf
            cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64 > "${jwt_secret_path}"
        else
            echo "Error: Cannot generate JWT secret - openssl or shuf not available" >&2
            return 1
        fi
        
        chmod 600 "${jwt_secret_path}"
        echo "✅ JWT secret generated"
    else
        echo "JWT secret already exists at ${jwt_secret_path}"
    fi
    
    return 0
}

# Validate Docker image exists
# Usage: validate_docker_image <image_tag>
validate_docker_image() {
    local image_tag="$1"
    
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image_tag}$"; then
        echo "✅ Docker image ${image_tag} exists"
        return 0
    else
        echo "❌ Docker image ${image_tag} not found" >&2
        return 1
    fi
}

# Get image size
# Usage: get_image_size <image_tag>
get_image_size() {
    local image_tag="$1"
    
    docker images --format "{{.Size}}" "${image_tag}" 2>/dev/null || echo "unknown"
}
