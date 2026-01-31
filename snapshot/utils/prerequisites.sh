#!/bin/bash
# Prerequisites checker for snapshot scripts
#
# This module provides functions to check for required tools and dependencies
# before running snapshot operations.

# Source logging if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/logging.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
fi

# Exit codes
EXIT_CODE_PREREQ_ERROR=3

# Minimum required Kurtosis version
MIN_KURTOSIS_VERSION="1.9.0"

# Compare semantic versions (v1.v2.v3 format)
# Returns 0 if $1 >= $2, 1 otherwise
# Usage: version_ge "1.9.0" "1.3.0"
version_ge() {
    local ver1="$1"
    local ver2="$2"

    # Remove 'v' prefix if present
    ver1="${ver1#v}"
    ver2="${ver2#v}"

    # Compare versions using sort
    if [ "$(printf '%s\n' "$ver1" "$ver2" | sort -V | head -n1)" = "$ver2" ]; then
        return 0  # ver1 >= ver2
    else
        return 1  # ver1 < ver2
    fi
}

# Check if Kurtosis CLI is installed and accessible
# Usage: check_kurtosis_cli
check_kurtosis_cli() {
    if ! command -v kurtosis &> /dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Kurtosis CLI is not installed or not in PATH"
            log_error "Install from: https://docs.kurtosis.com/install"
        else
            echo "Error: Kurtosis CLI is not installed or not in PATH" >&2
            echo "Install from: https://docs.kurtosis.com/install" >&2
        fi
        return 1
    fi

    # Extract version number
    local version_output
    version_output=$(kurtosis version 2>/dev/null || echo "")
    local cli_version
    cli_version=$(echo "$version_output" | grep "CLI Version" | awk '{print $3}' | tr -d ' ' || echo "")

    if [ -z "${cli_version}" ]; then
        if [ -n "$(type -t log_warn)" ]; then
            log_warn "Could not determine Kurtosis CLI version"
        fi
        cli_version="unknown"
    fi

    # Check version requirement
    if [ "$cli_version" != "unknown" ] && ! version_ge "$cli_version" "$MIN_KURTOSIS_VERSION"; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Kurtosis version $cli_version is too old (minimum required: $MIN_KURTOSIS_VERSION)"
            log_error ""
            log_error "The snapshot feature requires Kurtosis 1.9.0+ for:"
            log_error "  - plan.get_cluster_type() (required by ethereum-package)"
            log_error "  - plan.get_tolerations() (required by optimism-package)"
            log_error ""
            log_error "Please upgrade Kurtosis:"
            log_error "  - See: snapshot/KURTOSIS_UPGRADE_REQUIRED.md"
            log_error "  - Homebrew: brew upgrade kurtosis-tech/tap/kurtosis-cli"
            log_error "  - APT: sudo apt update && sudo apt install --only-upgrade kurtosis-cli"
            log_error "  - Manual: https://docs.kurtosis.com/upgrade/"
        else
            echo "Error: Kurtosis version $cli_version is too old (minimum: $MIN_KURTOSIS_VERSION)" >&2
            echo "See snapshot/KURTOSIS_UPGRADE_REQUIRED.md for upgrade instructions" >&2
        fi
        return 1
    fi

    if [ -n "$(type -t log_debug)" ]; then
        log_debug "Kurtosis CLI version: ${cli_version}"
    fi

    # Check engine version if engine is running
    local engine_version
    engine_version=$(kurtosis engine status 2>/dev/null | grep "Version:" | awk '{print $2}' | tr -d ' ' || echo "")
    if [ -n "$engine_version" ] && [ "$engine_version" != "unknown" ]; then
        if ! version_ge "$engine_version" "$MIN_KURTOSIS_VERSION"; then
            if [ -n "$(type -t log_warn)" ]; then
                log_warn "Kurtosis engine version $engine_version is too old (minimum: $MIN_KURTOSIS_VERSION)"
                log_warn "Restart the engine after upgrading: kurtosis engine restart"
            fi
        fi
        if [ -n "$(type -t log_debug)" ]; then
            log_debug "Kurtosis engine version: ${engine_version}"
        fi
    fi

    return 0
}

# Check if Docker is installed and daemon is running
# Usage: check_docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Docker is not installed or not in PATH"
            log_error "Install from: https://docs.docker.com/get-docker/"
        else
            echo "Error: Docker is not installed or not in PATH" >&2
            echo "Install from: https://docs.docker.com/get-docker/" >&2
        fi
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Docker daemon is not running"
            log_error "Start Docker daemon and try again"
        else
            echo "Error: Docker daemon is not running" >&2
            echo "Start Docker daemon and try again" >&2
        fi
        return 1
    fi
    
    if [ -n "$(type -t log_debug)" ]; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null || echo "unknown")
        log_debug "Docker version: ${docker_version}"
    fi
    
    return 0
}

# Check if docker-compose is available
# Usage: check_docker_compose
check_docker_compose() {
    local compose_available=false
    
    # Check for docker-compose (standalone)
    if command -v docker-compose &> /dev/null; then
        compose_available=true
        if [ -n "$(type -t log_debug)" ]; then
            local version
            version=$(docker-compose --version 2>/dev/null || echo "unknown")
            log_debug "docker-compose version: ${version}"
        fi
    # Check for docker compose (plugin)
    elif docker compose version &> /dev/null; then
        compose_available=true
        if [ -n "$(type -t log_debug)" ]; then
            local version
            version=$(docker compose version 2>/dev/null || echo "unknown")
            log_debug "docker compose version: ${version}"
        fi
    fi
    
    if [ "${compose_available}" = "false" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "docker-compose is not available"
            log_error "Install docker-compose or use Docker with compose plugin"
        else
            echo "Error: docker-compose is not available" >&2
            echo "Install docker-compose or use Docker with compose plugin" >&2
        fi
        return 1
    fi
    
    return 0
}

# Check if jq is installed
# Usage: check_jq
check_jq() {
    if ! command -v jq &> /dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "jq is not installed or not in PATH"
            log_error "Install from: https://stedolan.github.io/jq/download/"
        else
            echo "Error: jq is not installed or not in PATH" >&2
            echo "Install from: https://stedolan.github.io/jq/download/" >&2
        fi
        return 1
    fi
    
    if [ -n "$(type -t log_debug)" ]; then
        local version
        version=$(jq --version 2>/dev/null || echo "unknown")
        log_debug "jq version: ${version}"
    fi
    
    return 0
}

# Check if cast (foundry) is installed (optional but recommended)
# Usage: check_cast
check_cast() {
    if ! command -v cast &> /dev/null; then
        if [ -n "$(type -t log_warn)" ]; then
            log_warn "cast (foundry) is not installed (optional but recommended)"
            log_warn "Install from: https://book.getfoundry.sh/getting-started/installation"
        fi
        return 1
    fi
    
    if [ -n "$(type -t log_debug)" ]; then
        local version
        version=$(cast --version 2>/dev/null || echo "unknown")
        log_debug "cast version: ${version}"
    fi
    
    return 0
}

# Check all required tools
# Usage: check_required_tools
check_required_tools() {
    local errors=0
    
    if [ -n "$(type -t log_info)" ]; then
        log_info "Checking prerequisites..."
    fi
    
    if ! check_kurtosis_cli; then
        errors=$((errors + 1))
    fi
    
    if ! check_docker; then
        errors=$((errors + 1))
    fi
    
    if ! check_docker_compose; then
        errors=$((errors + 1))
    fi
    
    if ! check_jq; then
        errors=$((errors + 1))
    fi
    
    # cast is optional, just warn
    check_cast || true
    
    if [ ${errors} -gt 0 ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Prerequisites check failed: ${errors} error(s)"
        else
            echo "Error: Prerequisites check failed: ${errors} error(s)" >&2
        fi
        return 1
    fi
    
    if [ -n "$(type -t log_success)" ]; then
        log_success "All required prerequisites are available"
    fi
    
    return 0
}

# Check if Kurtosis enclave exists
# Usage: check_enclave_exists <enclave_name>
check_enclave_exists() {
    local enclave_name="$1"
    
    if [ -z "${enclave_name}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Enclave name is required"
        else
            echo "Error: Enclave name is required" >&2
        fi
        return 1
    fi
    
    # Check if enclave exists
    if ! kurtosis enclave inspect "${enclave_name}" &> /dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Enclave '${enclave_name}' does not exist"
            log_error "List enclaves with: kurtosis enclave ls"
        else
            echo "Error: Enclave '${enclave_name}' does not exist" >&2
            echo "List enclaves with: kurtosis enclave ls" >&2
        fi
        return 1
    fi
    
    if [ -n "$(type -t log_debug)" ]; then
        log_debug "Enclave '${enclave_name}' exists"
    fi
    
    return 0
}

# Check if output directory is writable
# Usage: check_output_dir <output_dir>
check_output_dir() {
    local output_dir="$1"
    
    if [ -z "${output_dir}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Output directory is required"
        else
            echo "Error: Output directory is required" >&2
        fi
        return 1
    fi
    
    # Create directory if it doesn't exist
    if [ ! -d "${output_dir}" ]; then
        if ! mkdir -p "${output_dir}" 2>/dev/null; then
            if [ -n "$(type -t log_error)" ]; then
                log_error "Cannot create output directory: ${output_dir}"
            else
                echo "Error: Cannot create output directory: ${output_dir}" >&2
            fi
            return 1
        fi
    fi
    
    # Check if directory is writable
    if [ ! -w "${output_dir}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Output directory is not writable: ${output_dir}"
        else
            echo "Error: Output directory is not writable: ${output_dir}" >&2
        fi
        return 1
    fi
    
    if [ -n "$(type -t log_debug)" ]; then
        log_debug "Output directory is writable: ${output_dir}"
    fi
    
    return 0
}

# Check disk space (optional check)
# Usage: check_disk_space <output_dir> <min_gb>
check_disk_space() {
    local output_dir="$1"
    local min_gb="${2:-10}"  # Default 10GB minimum
    
    if [ -z "${output_dir}" ]; then
        return 0  # Skip if no directory provided
    fi
    
    # Get available space in GB
    local available_gb
    if command -v df &> /dev/null; then
        available_gb=$(df -BG "${output_dir}" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "0")
        
        if [ "${available_gb}" -lt "${min_gb}" ]; then
            if [ -n "$(type -t log_warn)" ]; then
                log_warn "Low disk space: ${available_gb}GB available (recommended: ${min_gb}GB minimum)"
            else
                echo "Warning: Low disk space: ${available_gb}GB available (recommended: ${min_gb}GB minimum)" >&2
            fi
            return 1
        fi
    fi
    
    return 0
}
