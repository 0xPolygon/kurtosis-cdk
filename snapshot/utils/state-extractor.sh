#!/bin/bash
# Helper functions for L1 state extraction in snapshot mode

set -euo pipefail

# Source kurtosis-helpers.sh for common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/kurtosis-helpers.sh"

# Wait for finalized block on L1
# Usage: wait_for_finalized_block <enclave_name> <l1_rpc_url> <min_blocks>
wait_for_finalized_block() {
    local enclave_name="$1"
    local l1_rpc_url="$2"
    local min_blocks="${3:-1}"
    
    echo "Waiting for at least ${min_blocks} finalized blocks on L1..."
    
    local finalized_block=0
    local max_attempts=300  # 10 minutes with 2 second intervals
    local attempt=0
    
    while [ ${attempt} -lt ${max_attempts} ]; do
        finalized_block=$(cast block-number --rpc-url "${l1_rpc_url}" finalized 2>/dev/null || echo "0")
        latest_block=$(cast block-number --rpc-url "${l1_rpc_url}" latest 2>/dev/null || echo "0")
        
        echo "L1 blocks - Latest: ${latest_block}, Finalized: ${finalized_block}"
        
        if [ "${finalized_block}" -ge "${min_blocks}" ]; then
            echo "✅ Finalized block reached: ${finalized_block}"
            echo "${finalized_block}"
            return 0
        fi
        
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "Error: Did not reach ${min_blocks} finalized blocks within timeout" >&2
    return 1
}

# Wait for finalized slot on beacon chain
# Usage: wait_for_finalized_slot <beacon_url>
wait_for_finalized_slot() {
    local beacon_url="$1"
    
    if [ -z "${beacon_url}" ]; then
        echo "0"
        return 0
    fi
    
    echo "Waiting for finalized slot on beacon chain..."
    
    local finalized_slot=0
    local max_attempts=300  # 10 minutes with 2 second intervals
    local attempt=0
    
    while [ ${attempt} -lt ${max_attempts} ]; do
        local response=$(curl --silent "${beacon_url}/eth/v1/beacon/headers/finalized" 2>/dev/null || echo '{}')
        finalized_slot=$(echo "${response}" | jq --raw-output '.data.header.message.slot // 0' 2>/dev/null || echo "0")
        
        if [ "${finalized_slot}" != "0" ] && [ "${finalized_slot}" != "null" ]; then
            echo "✅ Finalized slot reached: ${finalized_slot}"
            echo "${finalized_slot}"
            return 0
        fi
        
        echo "L1 finalized slot: ${finalized_slot}"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "Error: Did not reach finalized slot within timeout" >&2
    return 1
}

# Extract datadir from container
# Usage: extract_datadir <enclave_name> <service_name> <src_path> <dest_path>
extract_datadir() {
    local enclave_name="$1"
    local service_name="$2"
    local src_path="$3"
    local dest_path="$4"

    echo "Extracting ${src_path} from ${service_name} to ${dest_path}..."

    # Create destination directory
    mkdir -p "${dest_path}"

    # Extract using tar via kurtosis service exec
    # Use tar to preserve permissions and directory structure
    # Note: kurtosis service exec doesn't use --command flag, just pass the command directly
    kurtosis service exec "${enclave_name}" "${service_name}" \
        tar czf - -C "$(dirname ${src_path})" "$(basename ${src_path})" 2>/dev/null | \
        tar xzf - -C "${dest_path}" 2>/dev/null || {
        echo "Error: Failed to extract datadir from ${service_name}" >&2
        return 1
    }

    echo "✅ Successfully extracted ${src_path} to ${dest_path}"
    return 0
}

# Verify state consistency between geth and lighthouse
# Usage: verify_state_consistency <geth_block> <lighthouse_slot> <l1_rpc_url> <beacon_url>
verify_state_consistency() {
    local geth_block="$1"
    local lighthouse_slot="$2"
    local l1_rpc_url="$3"
    local beacon_url="$4"
    
    echo "Verifying state consistency..."
    echo "Geth finalized block: ${geth_block}"
    echo "Lighthouse finalized slot: ${lighthouse_slot}"
    
    # Check if we have valid values
    if [ "${geth_block}" -eq 0 ] && [ "${lighthouse_slot}" -eq 0 ]; then
        echo "Warning: Both geth block and lighthouse slot are 0, cannot verify consistency"
        return 0
    fi
    
    # Try to get block number from slot (approximate)
    # In minimal preset, there are 8 slots per epoch, and blocks are produced every slot
    # So slot number should be approximately equal to block number
    if [ "${lighthouse_slot}" -gt 0 ] && [ "${geth_block}" -gt 0 ]; then
        local slot_block_diff=$((lighthouse_slot - geth_block))
        if [ ${slot_block_diff#-} -gt 10 ]; then
            echo "Warning: Large difference between slot (${lighthouse_slot}) and block (${geth_block}), difference: ${slot_block_diff}"
            echo "This may be normal depending on network configuration"
        else
            echo "✅ State consistency verified: slot and block are close (difference: ${slot_block_diff})"
        fi
    fi
    
    return 0
}

# Get L1 service names from enclave
# Usage: get_l1_service_names <enclave_name>
# Returns: space-separated list of service names (geth_service lighthouse_service)
get_l1_service_names() {
    local enclave_name="$1"

    echo "Getting L1 service names from enclave ${enclave_name}..." >&2

    # List all services and filter for L1 services
    # Note: kurtosis service ls doesn't support --format, it outputs a table by default
    # We need to parse the output (skip header lines and extract service names)
    local services=$(kurtosis service ls "${enclave_name}" 2>/dev/null | awk 'NR>2 {print $2}' || echo "")

    local geth_service=""
    local lighthouse_service=""

    # Look for standard service name patterns
    for service in ${services}; do
        if [[ "${service}" =~ ^el-.*-geth-.*$ ]] || [[ "${service}" =~ ^.*-geth-.*$ ]]; then
            geth_service="${service}"
        fi
        if [[ "${service}" =~ ^cl-.*-lighthouse-.*$ ]] || [[ "${service}" =~ ^.*-lighthouse-.*$ ]]; then
            lighthouse_service="${service}"
        fi
    done

    # Fallback to standard names if not found
    if [ -z "${geth_service}" ]; then
        geth_service="el-1-geth-lighthouse"
        echo "Warning: Could not find geth service, using default: ${geth_service}" >&2
    fi

    if [ -z "${lighthouse_service}" ]; then
        lighthouse_service="cl-1-lighthouse-geth"
        echo "Warning: Could not find lighthouse service, using default: ${lighthouse_service}" >&2
    fi
    
    echo "${geth_service} ${lighthouse_service}"
}
