#!/usr/bin/env bash
# Extract L2 contract addresses from running Kurtosis enclave
# This script queries the L2 chain to get deployed sovereign contract addresses

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/logging.sh"

# Usage: extract_l2_contracts <enclave_name> <output_dir>
extract_l2_contracts() {
    local enclave_name="$1"
    local output_dir="$2"

    log_info "Extracting L2 contract addresses from enclave: ${enclave_name}"

    # Get list of contract services in the enclave
    # The output format is: UUID NAME PORTS STATUS
    # We need to extract the NAME field (second column)
    local contract_services=$(kurtosis enclave inspect "${enclave_name}" 2>/dev/null | awk '{if ($2 ~ /^contracts-/) print $2}' || echo "")

    if [ -z "${contract_services}" ]; then
        log_warn "No contracts services found in enclave"
        return 0
    fi

    # Process each contracts service
    for service in ${contract_services}; do
        log_info "Extracting from service: ${service}"

        # Extract network ID from service name (e.g., contracts-001 -> 1)
        local network_id=$(echo "${service}" | grep -oP '(?<=contracts-)\d+' | sed 's/^0*//' | head -1)

        if [ -z "${network_id}" ]; then
            # Try without suffix
            network_id=$(echo "${service}" | grep -oP '\d+' | sed 's/^0*//' | head -1)
        fi

        if [ -z "${network_id}" ]; then
            log_warn "Could not extract network ID from service: ${service}, assuming network 1"
            network_id="1"
        fi

        log_info "Processing network ${network_id}..."

        # Download the actual L2 genesis artifact
        local genesis_artifact="genesis-$(printf '%03d' ${network_id})"
        local temp_dir="${output_dir}/.temp/genesis-${network_id}"
        mkdir -p "${temp_dir}"

        log_info "Downloading ${genesis_artifact} artifact..."

        local genesis_result="{}"
        if kurtosis files download "${enclave_name}" "${genesis_artifact}" "${temp_dir}" 2>/dev/null; then
            # Find the genesis.json file in the downloaded artifact
            local genesis_file=$(find "${temp_dir}" -name "genesis.json" -type f | head -1)
            if [ -n "${genesis_file}" ] && [ -f "${genesis_file}" ]; then
                genesis_result=$(cat "${genesis_file}")
                log_info "Found genesis.json in artifact"
            else
                log_warn "No genesis.json found in ${genesis_artifact} artifact"
            fi
        else
            log_warn "Could not download ${genesis_artifact} artifact"
        fi

        if [ "${genesis_result}" = "{}" ] || [ -z "${genesis_result}" ]; then
            log_warn "No genesis.json found for network ${network_id}"
            continue
        fi

        # Also read create-sovereign-genesis-output.json to get the address mappings
        local mapping_result=$(kurtosis service exec "${enclave_name}" "${service}" \
            "sh -c 'if [ -f /opt/output/create-sovereign-genesis-output.json ]; then cat /opt/output/create-sovereign-genesis-output.json; else echo \"{}\"; fi'" 2>/dev/null || echo "{}")

        # Extract L2 contract addresses from the mapping file
        local l2_ger_addr=$(echo "${mapping_result}" | jq -r '.genesisSCNames."AgglayerGERL2 proxy" // ""' 2>/dev/null || echo "")
        local l2_bridge_addr=$(echo "${mapping_result}" | jq -r '.genesisSCNames."AgglayerBridgeL2 proxy" // ""' 2>/dev/null || echo "")

        # Verify these addresses exist in the genesis
        # The genesis format has a .genesis array with objects containing address and bytecode
        if [ -n "${l2_ger_addr}" ]; then
            # Normalize address for comparison (lowercase, with 0x)
            local normalized_ger=$(echo "${l2_ger_addr}" | tr '[:upper:]' '[:lower:]')
            local found=$(echo "${genesis_result}" | jq -r --arg addr "${normalized_ger}" '.genesis[]? | select(.address | ascii_downcase == $addr) | .address' 2>/dev/null | head -1)
            if [ -z "${found}" ]; then
                log_warn "GER address ${l2_ger_addr} not found in genesis"
                l2_ger_addr=""
            else
                log_info "Verified GER ${l2_ger_addr} exists in genesis"
            fi
        fi

        if [ -n "${l2_bridge_addr}" ]; then
            # Normalize address for comparison (lowercase, with 0x)
            local normalized_bridge=$(echo "${l2_bridge_addr}" | tr '[:upper:]' '[:lower:]')
            local found=$(echo "${genesis_result}" | jq -r --arg addr "${normalized_bridge}" '.genesis[]? | select(.address | ascii_downcase == $addr) | .address' 2>/dev/null | head -1)
            if [ -z "${found}" ]; then
                log_warn "Bridge address ${l2_bridge_addr} not found in genesis"
                l2_bridge_addr=""
            else
                log_info "Verified Bridge ${l2_bridge_addr} exists in genesis"
            fi
        fi

        if [ -n "${l2_ger_addr}" ] && [ -n "${l2_bridge_addr}" ]; then
            # Create contracts file
            local contracts_file="${output_dir}/configs/${network_id}/l2-contracts.json"
            mkdir -p "$(dirname "${contracts_file}")"

            cat > "${contracts_file}" <<EOF
{
  "l2_ger_address": "${l2_ger_addr}",
  "l2_bridge_address": "${l2_bridge_addr}",
  "extracted_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "source": "genesis_artifact"
}
EOF
            log_success "Extracted L2 contracts for network ${network_id}"
            log_info "  GER: ${l2_ger_addr}"
            log_info "  Bridge: ${l2_bridge_addr}"
        else
            log_warn "Could not extract L2 contract addresses for network ${network_id}"
        fi

        # Cleanup temp dir
        rm -rf "${temp_dir}"
    done

    log_success "L2 contract extraction complete"
}

# Main execution
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <enclave_name> <output_dir>"
    exit 1
fi

extract_l2_contracts "$1" "$2"
