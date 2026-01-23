#!/bin/bash
# Helper functions for processing config files in snapshot mode
#
# This module provides functions to:
# - Read/write TOML and JSON config files
# - Convert service names and URLs from Kurtosis format to docker-compose format
# - Update agglayer config sections with multiple networks

set -euo pipefail

# Read JSON file and return content
# Usage: read_json_file <file_path>
read_json_file() {
    local file_path="$1"
    
    if [ ! -f "${file_path}" ]; then
        echo "Error: JSON file not found: ${file_path}" >&2
        return 1
    fi
    
    cat "${file_path}"
}

# Write JSON file with proper formatting
# Usage: write_json_file <file_path> <json_content>
write_json_file() {
    local file_path="$1"
    local json_content="$2"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "${file_path}")"
    
    # Use jq to format JSON if available, otherwise write as-is
    if command -v jq &> /dev/null; then
        echo "${json_content}" | jq '.' > "${file_path}"
    else
        echo "${json_content}" > "${file_path}"
    fi
}

# Read TOML file and return content
# Usage: read_toml_file <file_path>
read_toml_file() {
    local file_path="$1"
    
    if [ ! -f "${file_path}" ]; then
        echo "Error: TOML file not found: ${file_path}" >&2
        return 1
    fi
    
    cat "${file_path}"
}

# Write TOML file preserving structure
# Usage: write_toml_file <file_path> <toml_content>
write_toml_file() {
    local file_path="$1"
    local toml_content="$2"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "${file_path}")"
    
    echo "${toml_content}" > "${file_path}"
}

# Convert service name from Kurtosis format to docker-compose format
# Pattern: {service}{deployment_suffix} → {service}-{network_id}
# Example: cdk-node-002 → cdk-node-2
# Usage: convert_service_name <kurtosis_name> <deployment_suffix> <network_id>
convert_service_name() {
    local kurtosis_name="$1"
    local deployment_suffix="$2"
    local network_id="$3"
    
    # Remove deployment suffix and append network_id
    if [ -n "${deployment_suffix}" ]; then
        echo "${kurtosis_name}" | sed "s/${deployment_suffix}\$/-${network_id}/"
    else
        echo "${kurtosis_name}-${network_id}"
    fi
}

# Convert service URL from Kurtosis format to docker-compose format
# Pattern: http://{service}{deployment_suffix}:{port} → http://{service}-{network_id}:{port}
# Usage: convert_service_url <url> <deployment_suffix> <network_id>
convert_service_url() {
    local url="$1"
    local deployment_suffix="$2"
    local network_id="$3"
    
    if [ -z "${deployment_suffix}" ]; then
        echo "${url}"
        return 0
    fi
    
    # Replace service names in URLs
    # Pattern: http://service-002:port → http://service-2:port
    echo "${url}" | sed "s/\(http[s]*:\/\/[^:]*\)${deployment_suffix}\(:[0-9]*\)/\1-${network_id}\2/g"
}

# Replace service URLs in config content
# Usage: replace_urls_in_config <config_content> <deployment_suffix> <network_id>
replace_urls_in_config() {
    local config_content="$1"
    local deployment_suffix="$2"
    local network_id="$3"
    
    if [ -z "${deployment_suffix}" ]; then
        echo "${config_content}"
        return 0
    fi
    
    # Replace URLs in the config
    echo "${config_content}" | sed "s/\(http[s]*:\/\/[^:]*\)${deployment_suffix}\(:[0-9]*\)/\1-${network_id}\2/g"
}

# Replace ports in config content
# Usage: replace_ports_in_config <config_content> <port_mapping_json>
# port_mapping_json should be a JSON object with old_port -> new_port mappings
replace_ports_in_config() {
    local config_content="$1"
    local port_mapping_json="$2"
    local result="${config_content}"
    
    if [ -z "${port_mapping_json}" ] || [ "${port_mapping_json}" = "{}" ]; then
        echo "${result}"
        return 0
    fi
    
    # Extract port mappings and replace in config
    if command -v jq &> /dev/null; then
        local keys
        keys=$(echo "${port_mapping_json}" | jq -r 'keys[]' 2>/dev/null || echo "")
        
        while IFS= read -r key; do
            if [ -n "${key}" ]; then
                local value
                value=$(echo "${port_mapping_json}" | jq -r ".[\"${key}\"]" 2>/dev/null || echo "")
                if [ -n "${value}" ] && [ "${value}" != "null" ]; then
                    # Replace port numbers in URLs and config values
                    result=$(echo "${result}" | sed "s/:${key}\([^0-9]\)/:${value}\1/g")
                    result=$(echo "${result}" | sed "s/\"${key}\"/\"${value}\"/g")
                    result=$(echo "${result}" | sed "s/= ${key}$/= ${value}/g")
                fi
            fi
        done <<< "${keys}"
    fi
    
    echo "${result}"
}

# Update agglayer [full-node-rpcs] section with all networks
# Usage: update_agglayer_full_node_rpcs <config_content> <networks_json>
# networks_json should contain array of network objects with network_id, l2_rpc_name, deployment_suffix, http_rpc_port
update_agglayer_full_node_rpcs() {
    local config_content="$1"
    local networks_json="$2"
    local result="${config_content}"
    
    if [ -z "${networks_json}" ] || [ "${networks_json}" = "[]" ]; then
        echo "${result}"
        return 0
    fi
    
    # Find [full-node-rpcs] section
    local section_start
    section_start=$(echo "${result}" | grep -n "^\[full-node-rpcs\]" | cut -d: -f1 || echo "")
    
    if [ -z "${section_start}" ]; then
        echo "Warning: [full-node-rpcs] section not found in agglayer config" >&2
        echo "${result}"
        return 0
    fi
    
    # Find the end of the section (next [section] or end of file)
    local section_end
    section_end=$(echo "${result}" | tail -n +$((section_start + 1)) | grep -n "^\[" | head -1 | cut -d: -f1 || echo "")
    
    if [ -z "${section_end}" ]; then
        section_end=$(echo "${result}" | wc -l)
    else
        section_end=$((section_start + section_end - 1))
    fi
    
    # Extract lines before and after the section
    local before_section
    before_section=$(echo "${result}" | head -n $((section_start - 1)))
    local after_section
    after_section=$(echo "${result}" | tail -n +$((section_end + 1)))
    
    # Build new section content
    local new_section="[full-node-rpcs]"
    
    if command -v jq &> /dev/null; then
        local network_count
        network_count=$(echo "${networks_json}" | jq 'length' 2>/dev/null || echo "0")
        
        for i in $(seq 0 $((network_count - 1))); do
            local network_id
            network_id=$(echo "${networks_json}" | jq -r ".[${i}].network_id" 2>/dev/null || echo "")
            local l2_rpc_name
            l2_rpc_name=$(echo "${networks_json}" | jq -r ".[${i}].l2_rpc_name" 2>/dev/null || echo "cdk-erigon-rpc")
            local http_rpc_port
            http_rpc_port=$(echo "${networks_json}" | jq -r ".[${i}].http_rpc_port // 8123" 2>/dev/null || echo "8123")
            local sequencer_type
            sequencer_type=$(echo "${networks_json}" | jq -r ".[${i}].sequencer_type" 2>/dev/null || echo "")
            
            if [ -n "${network_id}" ] && [ "${network_id}" != "null" ] && [ "${network_id}" != "0" ]; then
                if [ "${sequencer_type}" = "op-geth" ]; then
                    # For OP-Geth, use op_el_rpc_url format
                    local op_el_rpc_url
                    op_el_rpc_url=$(echo "${networks_json}" | jq -r ".[${i}].op_el_rpc_url // \"http://op-geth-${network_id}:8545\"" 2>/dev/null || echo "http://op-geth-${network_id}:8545")
                    new_section="${new_section}"$'\n'"${network_id} = \"${op_el_rpc_url}\""
                else
                    # For CDK-Erigon, use standard format
                    new_section="${new_section}"$'\n'"${network_id} = \"http://${l2_rpc_name}-${network_id}:${http_rpc_port}\""
                fi
            fi
        done
    fi
    
    # Reconstruct config with new section
    if [ -n "${before_section}" ]; then
        result="${before_section}"$'\n'"${new_section}"
    else
        result="${new_section}"
    fi
    
    if [ -n "${after_section}" ]; then
        result="${result}"$'\n'"${after_section}"
    fi
    
    echo "${result}"
}

# Update agglayer [proof-signers] section with all networks
# Usage: update_agglayer_proof_signers <config_content> <networks_json>
# networks_json should contain array of network objects with network_id and l2_sequencer_address
update_agglayer_proof_signers() {
    local config_content="$1"
    local networks_json="$2"
    local result="${config_content}"
    
    if [ -z "${networks_json}" ] || [ "${networks_json}" = "[]" ]; then
        echo "${result}"
        return 0
    fi
    
    # Find [proof-signers] section
    local section_start
    section_start=$(echo "${result}" | grep -n "^\[proof-signers\]" | cut -d: -f1 || echo "")
    
    if [ -z "${section_start}" ]; then
        echo "Warning: [proof-signers] section not found in agglayer config" >&2
        echo "${result}"
        return 0
    fi
    
    # Find the end of the section (next [section] or end of file)
    local section_end
    section_end=$(echo "${result}" | tail -n +$((section_start + 1)) | grep -n "^\[" | head -1 | cut -d: -f1 || echo "")
    
    if [ -z "${section_end}" ]; then
        section_end=$(echo "${result}" | wc -l)
    else
        section_end=$((section_start + section_end - 1))
    fi
    
    # Extract lines before and after the section
    local before_section
    before_section=$(echo "${result}" | head -n $((section_start - 1)))
    local after_section
    after_section=$(echo "${result}" | tail -n +$((section_end + 1)))
    
    # Build new section content
    local new_section="[proof-signers]"
    
    if command -v jq &> /dev/null; then
        local network_count
        network_count=$(echo "${networks_json}" | jq 'length' 2>/dev/null || echo "0")
        
        for i in $(seq 0 $((network_count - 1))); do
            local network_id
            network_id=$(echo "${networks_json}" | jq -r ".[${i}].network_id" 2>/dev/null || echo "")
            local sequencer_address
            sequencer_address=$(echo "${networks_json}" | jq -r ".[${i}].l2_sequencer_address" 2>/dev/null || echo "")
            
            if [ -n "${network_id}" ] && [ "${network_id}" != "null" ] && [ "${network_id}" != "0" ] && [ -n "${sequencer_address}" ] && [ "${sequencer_address}" != "null" ]; then
                new_section="${new_section}"$'\n'"${network_id} = \"${sequencer_address}\""
            fi
        done
    fi
    
    # Reconstruct config with new section
    if [ -n "${before_section}" ]; then
        result="${before_section}"$'\n'"${new_section}"
    else
        result="${new_section}"
    fi
    
    if [ -n "${after_section}" ]; then
        result="${result}"$'\n'"${after_section}"
    fi
    
    echo "${result}"
}

# Validate TOML syntax (basic check)
# Usage: validate_toml <file_path>
validate_toml() {
    local file_path="$1"
    
    if [ ! -f "${file_path}" ]; then
        echo "Error: TOML file not found: ${file_path}" >&2
        return 1
    fi
    
    # Basic validation: check for balanced brackets
    local open_brackets
    open_brackets=$(grep -o '\[' "${file_path}" | wc -l || echo "0")
    local close_brackets
    close_brackets=$(grep -o '\]' "${file_path}" | wc -l || echo "0")
    
    if [ "${open_brackets}" != "${close_brackets}" ]; then
        echo "Warning: Unbalanced brackets in TOML file: ${file_path}" >&2
        return 1
    fi
    
    return 0
}

# Validate JSON syntax
# Usage: validate_json <file_path>
validate_json() {
    local file_path="$1"
    
    if [ ! -f "${file_path}" ]; then
        echo "Error: JSON file not found: ${file_path}" >&2
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        jq empty "${file_path}" 2>/dev/null || {
            echo "Error: Invalid JSON in file: ${file_path}" >&2
            return 1
        }
    else
        # Basic check without jq
        if ! grep -q '^{' "${file_path}" && ! grep -q '^\[' "${file_path}"; then
            echo "Warning: File may not be valid JSON: ${file_path}" >&2
        fi
    fi
    
    return 0
}
