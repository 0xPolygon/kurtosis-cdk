#!/bin/bash
# Validation utilities for snapshot scripts
#
# This module provides comprehensive validation functions for:
# - Network configurations
# - Config files (TOML, JSON)
# - Docker images
# - Docker compose files
# - L1 state
# - Required files

# Source logging if available
if [ -f "$(dirname "${BASH_SOURCE[0]}")/logging.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
fi

# Exit codes
EXIT_CODE_VALIDATION_ERROR=2

# Valid sequencer/consensus type combinations
VALID_CDK_ERIGON_CONSENSUS=("rollup" "cdk-validium" "pessimistic" "ecdsa-multisig")
VALID_OP_GETH_CONSENSUS=("rollup" "pessimistic" "ecdsa-multisig" "fep")

# Validate hex address format
# Usage: is_valid_address <address>
is_valid_address() {
    local address="$1"
    
    # Check if it's a valid hex address (0x followed by 40 hex chars)
    if [[ "${address}" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
        return 0
    fi
    
    return 1
}

# Validate hex private key format
# Usage: is_valid_private_key <key>
is_valid_private_key() {
    local key="$1"
    
    # Check if it's a valid hex private key (0x followed by 64 hex chars)
    if [[ "${key}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        return 0
    fi
    
    return 1
}

# Validate sequencer/consensus type combination
# Usage: is_valid_sequencer_consensus <sequencer_type> <consensus_type>
is_valid_sequencer_consensus() {
    local sequencer_type="$1"
    local consensus_type="$2"
    local valid_types=()
    
    case "${sequencer_type}" in
        "cdk-erigon")
            valid_types=("${VALID_CDK_ERIGON_CONSENSUS[@]}")
            ;;
        "op-geth")
            valid_types=("${VALID_OP_GETH_CONSENSUS[@]}")
            ;;
        *)
            return 1
            ;;
    esac
    
    for valid_type in "${valid_types[@]}"; do
        if [ "${consensus_type}" = "${valid_type}" ]; then
            return 0
        fi
    done
    
    return 1
}

# Validate single network config
# Usage: validate_network_config <network_config_json>
validate_network_config() {
    local network_config="$1"
    local errors=0
    
    if ! command -v jq &> /dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "jq is required for network config validation"
        else
            echo "Error: jq is required for network config validation" >&2
        fi
        return 1
    fi
    
    # Check required fields
    local required_fields=("sequencer_type" "consensus_type" "deployment_suffix" "l2_chain_id" "network_id")
    for field in "${required_fields[@]}"; do
        local value
        value=$(echo "${network_config}" | jq -r ".${field} // \"\"" 2>/dev/null || echo "")
        if [ -z "${value}" ] || [ "${value}" = "null" ]; then
            if [ -n "$(type -t log_error)" ]; then
                log_error "Missing required field: ${field}"
            else
                echo "Error: Missing required field: ${field}" >&2
            fi
            errors=$((errors + 1))
        fi
    done
    
    # Validate sequencer type
    local sequencer_type
    sequencer_type=$(echo "${network_config}" | jq -r '.sequencer_type // ""' 2>/dev/null || echo "")
    if [ "${sequencer_type}" != "cdk-erigon" ] && [ "${sequencer_type}" != "op-geth" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Invalid sequencer_type: ${sequencer_type} (must be 'cdk-erigon' or 'op-geth')"
        else
            echo "Error: Invalid sequencer_type: ${sequencer_type}" >&2
        fi
        errors=$((errors + 1))
    fi
    
    # Validate consensus type
    local consensus_type
    consensus_type=$(echo "${network_config}" | jq -r '.consensus_type // ""' 2>/dev/null || echo "")
    if ! is_valid_sequencer_consensus "${sequencer_type}" "${consensus_type}"; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Invalid consensus_type '${consensus_type}' for sequencer_type '${sequencer_type}'"
        else
            echo "Error: Invalid consensus_type '${consensus_type}' for sequencer_type '${sequencer_type}'" >&2
        fi
        errors=$((errors + 1))
    fi
    
    # Validate addresses
    local address_fields=("l2_sequencer_address" "l2_aggregator_address" "l2_admin_address" "l2_sovereignadmin_address")
    for field in "${address_fields[@]}"; do
        local address
        address=$(echo "${network_config}" | jq -r ".${field} // \"\"" 2>/dev/null || echo "")
        if [ -n "${address}" ] && [ "${address}" != "null" ]; then
            if ! is_valid_address "${address}"; then
                if [ -n "$(type -t log_error)" ]; then
                    log_error "Invalid address format in ${field}: ${address}"
                else
                    echo "Error: Invalid address format in ${field}: ${address}" >&2
                fi
                errors=$((errors + 1))
            fi
        fi
    done
    
    # Validate private keys
    local key_fields=("l2_sequencer_private_key" "l2_aggregator_private_key" "l2_admin_private_key" "l2_sovereignadmin_private_key")
    for field in "${key_fields[@]}"; do
        local key
        key=$(echo "${network_config}" | jq -r ".${field} // \"\"" 2>/dev/null || echo "")
        if [ -n "${key}" ] && [ "${key}" != "null" ]; then
            if ! is_valid_private_key "${key}"; then
                if [ -n "$(type -t log_error)" ]; then
                    log_error "Invalid private key format in ${field}"
                else
                    echo "Error: Invalid private key format in ${field}" >&2
                fi
                errors=$((errors + 1))
            fi
        fi
    done
    
    # Validate numeric fields
    local l2_chain_id
    l2_chain_id=$(echo "${network_config}" | jq -r '.l2_chain_id // 0' 2>/dev/null || echo "0")
    if [ "${l2_chain_id}" -le 0 ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Invalid l2_chain_id: ${l2_chain_id} (must be > 0)"
        else
            echo "Error: Invalid l2_chain_id: ${l2_chain_id}" >&2
        fi
        errors=$((errors + 1))
    fi
    
    local network_id
    network_id=$(echo "${network_config}" | jq -r '.network_id // 0' 2>/dev/null || echo "0")
    if [ "${network_id}" -le 0 ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Invalid network_id: ${network_id} (must be > 0)"
        else
            echo "Error: Invalid network_id: ${network_id}" >&2
        fi
        errors=$((errors + 1))
    fi
    
    return ${errors}
}

# Validate all network configs
# Usage: validate_networks_config <networks_json_file>
validate_networks_config() {
    local networks_file="$1"
    local errors=0
    
    if [ ! -f "${networks_file}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Networks config file not found: ${networks_file}"
        else
            echo "Error: Networks config file not found: ${networks_file}" >&2
        fi
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "jq is required for network config validation"
        else
            echo "Error: jq is required for network config validation" >&2
        fi
        return 1
    fi
    
    # Validate JSON syntax
    if ! jq empty "${networks_file}" 2>/dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Invalid JSON syntax in networks config file"
        else
            echo "Error: Invalid JSON syntax in networks config file" >&2
        fi
        return 1
    fi
    
    # Get networks array
    local networks_array
    networks_array=$(jq -c '.networks // []' "${networks_file}" 2>/dev/null || echo "[]")
    
    if [ "${networks_array}" = "[]" ]; then
        if [ -n "$(type -t log_warn)" ]; then
            log_warn "No networks found in config file"
        fi
        return 0
    fi
    
    local network_count
    network_count=$(echo "${networks_array}" | jq 'length' 2>/dev/null || echo "0")
    
    if [ -n "$(type -t log_info)" ]; then
        log_info "Validating ${network_count} network(s)..."
    fi
    
    # Track unique values for uniqueness validation
    local deployment_suffixes=()
    local chain_ids=()
    local network_ids=()
    
    # Validate each network
    for ((i=0; i<network_count; i++)); do
        local network_config
        network_config=$(echo "${networks_array}" | jq -c ".[${i}]" 2>/dev/null || echo "{}")
        
        if [ -n "$(type -t log_debug)" ]; then
            log_debug "Validating network ${i}..."
        fi
        
        if ! validate_network_config "${network_config}"; then
            errors=$((errors + 1))
        fi
        
        # Check uniqueness
        local deployment_suffix
        deployment_suffix=$(echo "${network_config}" | jq -r '.deployment_suffix // ""' 2>/dev/null || echo "")
        local l2_chain_id
        l2_chain_id=$(echo "${network_config}" | jq -r '.l2_chain_id // 0' 2>/dev/null || echo "0")
        local network_id
        network_id=$(echo "${network_config}" | jq -r '.network_id // 0' 2>/dev/null || echo "0")
        
        # Check for duplicate deployment_suffix
        for existing_suffix in "${deployment_suffixes[@]}"; do
            if [ "${deployment_suffix}" = "${existing_suffix}" ]; then
                if [ -n "$(type -t log_error)" ]; then
                    log_error "Duplicate deployment_suffix: ${deployment_suffix}"
                else
                    echo "Error: Duplicate deployment_suffix: ${deployment_suffix}" >&2
                fi
                errors=$((errors + 1))
            fi
        done
        
        # Check for duplicate chain_id
        for existing_chain_id in "${chain_ids[@]}"; do
            if [ "${l2_chain_id}" = "${existing_chain_id}" ]; then
                if [ -n "$(type -t log_error)" ]; then
                    log_error "Duplicate l2_chain_id: ${l2_chain_id}"
                else
                    echo "Error: Duplicate l2_chain_id: ${l2_chain_id}" >&2
                fi
                errors=$((errors + 1))
            fi
        done
        
        # Check for duplicate network_id
        for existing_network_id in "${network_ids[@]}"; do
            if [ "${network_id}" = "${existing_network_id}" ]; then
                if [ -n "$(type -t log_error)" ]; then
                    log_error "Duplicate network_id: ${network_id}"
                else
                    echo "Error: Duplicate network_id: ${network_id}" >&2
                fi
                errors=$((errors + 1))
            fi
        done
        
        # Add to tracking arrays
        deployment_suffixes+=("${deployment_suffix}")
        chain_ids+=("${l2_chain_id}")
        network_ids+=("${network_id}")
    done
    
    if [ ${errors} -eq 0 ]; then
        if [ -n "$(type -t log_success)" ]; then
            log_success "All ${network_count} network(s) validated successfully"
        fi
        return 0
    else
        if [ -n "$(type -t log_error)" ]; then
            log_error "Network validation failed: ${errors} error(s)"
        else
            echo "Error: Network validation failed: ${errors} error(s)" >&2
        fi
        return 1
    fi
}

# Validate config file syntax
# Usage: validate_config_file <file_path> <file_type>
# file_type: "json" or "toml"
validate_config_file() {
    local file_path="$1"
    local file_type="$2"
    local errors=0
    
    if [ ! -f "${file_path}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Config file not found: ${file_path}"
        else
            echo "Error: Config file not found: ${file_path}" >&2
        fi
        return 1
    fi
    
    # Check file is readable
    if [ ! -r "${file_path}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Config file is not readable: ${file_path}"
        else
            echo "Error: Config file is not readable: ${file_path}" >&2
        fi
        return 1
    fi
    
    case "${file_type}" in
        "json")
            if command -v jq &> /dev/null; then
                if ! jq empty "${file_path}" 2>/dev/null; then
                    if [ -n "$(type -t log_error)" ]; then
                        log_error "Invalid JSON syntax in: ${file_path}"
                    else
                        echo "Error: Invalid JSON syntax in: ${file_path}" >&2
                    fi
                    errors=$((errors + 1))
                fi
            else
                if [ -n "$(type -t log_warn)" ]; then
                    log_warn "jq not available, skipping JSON validation"
                fi
            fi
            ;;
        "toml")
            # Basic TOML validation (check for common syntax errors)
            # Full TOML validation would require a TOML parser
            if grep -q "^\[.*\]$" "${file_path}" 2>/dev/null || grep -q "^[^#].*=" "${file_path}" 2>/dev/null; then
                # Basic structure check passed
                if [ -n "$(type -t log_debug)" ]; then
                    log_debug "TOML file structure appears valid: ${file_path}"
                fi
            else
                if [ -n "$(type -t log_warn)" ]; then
                    log_warn "TOML file may be empty or invalid: ${file_path}"
                fi
            fi
            ;;
        *)
            if [ -n "$(type -t log_error)" ]; then
                log_error "Unknown file type: ${file_type} (must be 'json' or 'toml')"
            else
                echo "Error: Unknown file type: ${file_type}" >&2
            fi
            errors=$((errors + 1))
            ;;
    esac
    
    return ${errors}
}

# Validate Docker image
# Usage: validate_docker_image <image_tag>
validate_docker_image() {
    local image_tag="$1"
    local errors=0
    
    if [ -z "${image_tag}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Image tag is required"
        else
            echo "Error: Image tag is required" >&2
        fi
        return 1
    fi
    
    # Check if image exists
    if ! docker image inspect "${image_tag}" &> /dev/null; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Docker image not found: ${image_tag}"
        else
            echo "Error: Docker image not found: ${image_tag}" >&2
        fi
        return 1
    fi
    
    # Check image size (should be reasonable)
    local image_size
    image_size=$(docker image inspect "${image_tag}" --format '{{.Size}}' 2>/dev/null || echo "0")
    if [ "${image_size}" = "0" ]; then
        if [ -n "$(type -t log_warn)" ]; then
            log_warn "Could not determine image size for: ${image_tag}"
        fi
    else
        if [ -n "$(type -t log_debug)" ]; then
            log_debug "Image size: ${image_size} bytes"
        fi
    fi
    
    return 0
}

# Validate docker-compose file
# Usage: validate_docker_compose <compose_file>
validate_docker_compose() {
    local compose_file="$1"
    local errors=0
    
    if [ ! -f "${compose_file}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Docker compose file not found: ${compose_file}"
        else
            echo "Error: Docker compose file not found: ${compose_file}" >&2
        fi
        return 1
    fi
    
    # Check syntax using docker-compose
    if command -v docker-compose &> /dev/null; then
        if ! docker-compose -f "${compose_file}" config &> /dev/null; then
            if [ -n "$(type -t log_error)" ]; then
                log_error "Invalid docker-compose syntax in: ${compose_file}"
            else
                echo "Error: Invalid docker-compose syntax in: ${compose_file}" >&2
            fi
            errors=$((errors + 1))
        fi
    elif docker compose version &> /dev/null; then
        if ! docker compose -f "${compose_file}" config &> /dev/null; then
            if [ -n "$(type -t log_error)" ]; then
                log_error "Invalid docker-compose syntax in: ${compose_file}"
            else
                echo "Error: Invalid docker-compose syntax in: ${compose_file}" >&2
            fi
            errors=$((errors + 1))
        fi
    else
        if [ -n "$(type -t log_warn)" ]; then
            log_warn "docker-compose not available, skipping syntax validation"
        fi
    fi
    
    return ${errors}
}

# Validate L1 state directory
# Usage: validate_l1_state <l1_state_dir>
validate_l1_state() {
    local l1_state_dir="$1"
    local errors=0
    
    if [ ! -d "${l1_state_dir}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "L1 state directory not found: ${l1_state_dir}"
        else
            echo "Error: L1 state directory not found: ${l1_state_dir}" >&2
        fi
        return 1
    fi
    
    # Check for geth datadir
    local geth_dir="${l1_state_dir}/geth"
    if [ ! -d "${geth_dir}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Geth datadir not found: ${geth_dir}"
        else
            echo "Error: Geth datadir not found: ${geth_dir}" >&2
        fi
        errors=$((errors + 1))
    else
        # Check for chaindata
        if [ ! -d "${geth_dir}/geth/chaindata" ]; then
            if [ -n "$(type -t log_warn)" ]; then
                log_warn "Geth chaindata not found (may be in different location)"
            fi
        fi
    fi
    
    # Check for lighthouse datadir
    local lighthouse_dir="${l1_state_dir}/lighthouse"
    if [ ! -d "${lighthouse_dir}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Lighthouse datadir not found: ${lighthouse_dir}"
        else
            echo "Error: Lighthouse datadir not found: ${lighthouse_dir}" >&2
        fi
        errors=$((errors + 1))
    fi
    
    return ${errors}
}

# Validate required files exist
# Usage: validate_required_files <output_dir> <file_list>
# file_list is a space-separated list of relative paths from output_dir
validate_required_files() {
    local output_dir="$1"
    shift
    local file_list=("$@")
    local errors=0
    
    if [ ! -d "${output_dir}" ]; then
        if [ -n "$(type -t log_error)" ]; then
            log_error "Output directory not found: ${output_dir}"
        else
            echo "Error: Output directory not found: ${output_dir}" >&2
        fi
        return 1
    fi
    
    for file_path in "${file_list[@]}"; do
        local full_path="${output_dir}/${file_path}"
        if [ ! -f "${full_path}" ] && [ ! -d "${full_path}" ]; then
            if [ -n "$(type -t log_error)" ]; then
                log_error "Required file/directory not found: ${full_path}"
            else
                echo "Error: Required file/directory not found: ${full_path}" >&2
            fi
            errors=$((errors + 1))
        fi
    done
    
    return ${errors}
}
