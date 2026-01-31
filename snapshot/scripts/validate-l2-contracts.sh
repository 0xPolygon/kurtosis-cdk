#!/bin/bash
# Validation script for L2 Bridge contract extraction and configuration
#
# This script checks if L2 Bridge and GER contracts were properly:
# 1. Extracted to l2-contracts.json
# 2. Injected into aggkit-config.toml
# 3. Included in summary.json

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"

# Default values
OUTPUT_DIR=""

# Print usage
usage() {
    cat <<EOF
Usage: $0 --output-dir <snapshot-output-directory>

Validate L2 Bridge contract extraction and configuration in snapshot.

Options:
    --output-dir DIR    Snapshot output directory to validate (required)
    -h, --help          Show this help message

Example:
    $0 --output-dir ./snapshot-output
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "${OUTPUT_DIR}" ]; then
    echo "Error: --output-dir is required" >&2
    usage
fi

if [ ! -d "${OUTPUT_DIR}" ]; then
    echo "Error: Output directory does not exist: ${OUTPUT_DIR}" >&2
    exit 1
fi

log_section "Validating L2 Bridge Contract Extraction"

# Track validation results
TOTAL_NETWORKS=0
CONTRACTS_JSON_OK=0
AGGKIT_CONFIG_OK=0
SUMMARY_OK=0
ALL_OK=true

# Find all network config directories (numeric directories)
log_info "Scanning for network configurations..."

for network_dir in "${OUTPUT_DIR}/configs"/*/; do
    if [ ! -d "$network_dir" ]; then
        continue
    fi

    # Skip non-numeric directories (like 'agglayer')
    network_id=$(basename "$network_dir")
    if ! [[ "$network_id" =~ ^[0-9]+$ ]]; then
        continue
    fi

    TOTAL_NETWORKS=$((TOTAL_NETWORKS + 1))

    echo ""
    log_section "Network ${network_id}"

    # Check 1: l2-contracts.json exists and has valid addresses
    log_info "Checking l2-contracts.json..."
    contracts_file="${network_dir}/l2-contracts.json"

    if [ -f "$contracts_file" ]; then
        l2_ger=$(jq -r '.l2_ger_address // ""' "$contracts_file" 2>/dev/null || echo "")
        l2_bridge=$(jq -r '.l2_bridge_address // ""' "$contracts_file" 2>/dev/null || echo "")

        if [ -n "$l2_ger" ] && [ "$l2_ger" != "null" ] && [[ "$l2_ger" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
            log_success "L2 GER address: ${l2_ger}"
        else
            log_error "Invalid or missing L2 GER address: ${l2_ger}"
            ALL_OK=false
        fi

        if [ -n "$l2_bridge" ] && [ "$l2_bridge" != "null" ] && [[ "$l2_bridge" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
            log_success "L2 Bridge address: ${l2_bridge}"
            CONTRACTS_JSON_OK=$((CONTRACTS_JSON_OK + 1))
        else
            log_error "Invalid or missing L2 Bridge address: ${l2_bridge}"
            ALL_OK=false
        fi
    else
        log_error "l2-contracts.json not found"
        ALL_OK=false
    fi

    # Check 2: aggkit-config.toml has the addresses
    log_info "Checking aggkit-config.toml..."
    config_file="${network_dir}/aggkit-config.toml"

    if [ -f "$config_file" ]; then
        # Check L2Config.BridgeAddr
        if grep -q "^BridgeAddr = \"0x" "$config_file"; then
            bridge_addr=$(grep "^BridgeAddr" "$config_file" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1)
            log_success "L2Config.BridgeAddr: ${bridge_addr}"

            # Verify it matches l2-contracts.json
            if [ -n "$l2_bridge" ] && [ "$bridge_addr" = "$l2_bridge" ]; then
                log_success "BridgeAddr matches l2-contracts.json"
            elif [ -n "$l2_bridge" ]; then
                log_warn "BridgeAddr mismatch: config has ${bridge_addr}, l2-contracts.json has ${l2_bridge}"
                ALL_OK=false
            fi
        else
            log_error "L2Config.BridgeAddr not set or commented out"
            ALL_OK=false
        fi

        # Check L2Config.GlobalExitRootAddr
        if grep -q "^GlobalExitRootAddr = \"0x" "$config_file"; then
            ger_addr=$(grep "^GlobalExitRootAddr" "$config_file" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1)
            log_success "L2Config.GlobalExitRootAddr: ${ger_addr}"

            # Verify it matches l2-contracts.json
            if [ -n "$l2_ger" ] && [ "$ger_addr" = "$l2_ger" ]; then
                log_success "GlobalExitRootAddr matches l2-contracts.json"
            elif [ -n "$l2_ger" ]; then
                log_warn "GlobalExitRootAddr mismatch: config has ${ger_addr}, l2-contracts.json has ${l2_ger}"
                ALL_OK=false
            fi
        else
            log_error "L2Config.GlobalExitRootAddr not set or commented out"
            ALL_OK=false
        fi

        # Check if BridgeL2Sync section exists and is not commented out
        if grep -q "^\[BridgeL2Sync\]" "$config_file"; then
            log_success "[BridgeL2Sync] section exists"

            # Check if it has a valid BridgeAddr
            bridge_l2_sync_section=$(sed -n '/^\[BridgeL2Sync\]/,/^\[/p' "$config_file")
            if echo "$bridge_l2_sync_section" | grep -q "^BridgeAddr = \"0x"; then
                bridge_sync_addr=$(echo "$bridge_l2_sync_section" | grep "^BridgeAddr" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1)
                log_success "[BridgeL2Sync].BridgeAddr: ${bridge_sync_addr}"
                AGGKIT_CONFIG_OK=$((AGGKIT_CONFIG_OK + 1))
            else
                log_warn "[BridgeL2Sync].BridgeAddr not set or commented out"
                ALL_OK=false
            fi
        else
            log_warn "[BridgeL2Sync] section not found or commented out"
            ALL_OK=false
        fi
    else
        log_error "aggkit-config.toml not found"
        ALL_OK=false
    fi

    # Check 3: Genesis contains the addresses
    log_info "Checking genesis.json..."
    genesis_file="${network_dir}/genesis.json"

    if [ -f "$genesis_file" ]; then
        # Check if genesis has the addresses (both CDK and Geth formats)
        if [ -n "$l2_bridge" ]; then
            normalized_bridge=$(echo "$l2_bridge" | tr '[:upper:]' '[:lower:]')

            # Try CDK format (.genesis[])
            found=$(jq -r --arg addr "$normalized_bridge" '.genesis[]? | select(.address | ascii_downcase == $addr) | .address' "$genesis_file" 2>/dev/null | head -1 || echo "")

            # Try Geth format (.alloc{})
            if [ -z "$found" ]; then
                found=$(jq -r --arg addr "$normalized_bridge" '.alloc | to_entries[] | select(.key | ascii_downcase == $addr) | .key' "$genesis_file" 2>/dev/null | head -1 || echo "")
            fi

            if [ -n "$found" ]; then
                log_success "L2 Bridge found in genesis at ${found}"
            else
                log_warn "L2 Bridge ${l2_bridge} not found in genesis (may be deployed at runtime)"
            fi
        fi

        if [ -n "$l2_ger" ]; then
            normalized_ger=$(echo "$l2_ger" | tr '[:upper:]' '[:lower:]')

            # Try CDK format (.genesis[])
            found=$(jq -r --arg addr "$normalized_ger" '.genesis[]? | select(.address | ascii_downcase == $addr) | .address' "$genesis_file" 2>/dev/null | head -1 || echo "")

            # Try Geth format (.alloc{})
            if [ -z "$found" ]; then
                found=$(jq -r --arg addr "$normalized_ger" '.alloc | to_entries[] | select(.key | ascii_downcase == $addr) | .key' "$genesis_file" 2>/dev/null | head -1 || echo "")
            fi

            if [ -n "$found" ]; then
                log_success "L2 GER found in genesis at ${found}"
            else
                log_warn "L2 GER ${l2_ger} not found in genesis (may be deployed at runtime)"
            fi
        fi
    else
        log_warn "genesis.json not found"
    fi
done

# Check 4: summary.json includes L2 contracts
echo ""
log_section "Checking summary.json"

summary_file="${OUTPUT_DIR}/summary.json"
if [ -f "$summary_file" ]; then
    network_count=$(jq '.l2_networks | length' "$summary_file" 2>/dev/null || echo "0")
    log_info "Found ${network_count} L2 network(s) in summary"

    for i in $(seq 0 $((network_count - 1))); do
        network_id=$(jq -r ".l2_networks[$i].network_id" "$summary_file" 2>/dev/null || echo "")
        l2_ger=$(jq -r ".l2_networks[$i].contracts.l2_global_exit_root // \"\"" "$summary_file" 2>/dev/null || echo "")
        l2_bridge=$(jq -r ".l2_networks[$i].contracts.l2_bridge // \"\"" "$summary_file" 2>/dev/null || echo "")

        echo ""
        log_info "Network ${network_id} in summary:"

        if [ -n "$l2_ger" ] && [ "$l2_ger" != "null" ] && [[ "$l2_ger" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
            log_success "L2 GER: ${l2_ger}"
        else
            log_warn "L2 GER not in summary or invalid"
        fi

        if [ -n "$l2_bridge" ] && [ "$l2_bridge" != "null" ] && [[ "$l2_bridge" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
            log_success "L2 Bridge: ${l2_bridge}"
            SUMMARY_OK=$((SUMMARY_OK + 1))
        else
            log_warn "L2 Bridge not in summary or invalid"
        fi
    done
else
    log_error "summary.json not found"
    ALL_OK=false
fi

# Print summary
echo ""
echo "========================================"
log_section "Validation Summary"
echo "========================================"
echo ""
log_info "Total networks found: ${TOTAL_NETWORKS}"
log_info "Networks with valid l2-contracts.json: ${CONTRACTS_JSON_OK}/${TOTAL_NETWORKS}"
log_info "Networks with valid aggkit config: ${AGGKIT_CONFIG_OK}/${TOTAL_NETWORKS}"
log_info "Networks in summary with L2 contracts: ${SUMMARY_OK}/${TOTAL_NETWORKS}"
echo ""

if [ "$ALL_OK" = true ] && [ "$CONTRACTS_JSON_OK" -eq "$TOTAL_NETWORKS" ] && [ "$AGGKIT_CONFIG_OK" -eq "$TOTAL_NETWORKS" ]; then
    log_success "✅ All validations passed!"
    exit 0
else
    log_error "❌ Some validations failed. See above for details."
    echo ""
    echo "Common issues:"
    echo "  1. L2 contracts not extracted - check extract-l2-contracts.sh logs"
    echo "  2. Config injection failed - check process-configs.sh logs"
    echo "  3. create-sovereign-genesis-output.json not found in contracts service"
    echo ""
    echo "For troubleshooting, see: snapshot/L2_BRIDGE_FIX_SUMMARY.md"
    exit 1
fi
