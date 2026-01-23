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
    
    # Check version (basic check)
    local version
    version=$(kurtosis version 2>/dev/null || echo "")
    if [ -z "${version}" ]; then
        if [ -n "$(type -t log_warn)" ]; then
            log_warn "Could not determine Kurtosis version"
        fi
    else
        if [ -n "$(type -t log_debug)" ]; then
            log_debug "Kurtosis version: ${version}"
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
