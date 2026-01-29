#!/bin/bash
# Export L1 state to genesis file
#
# This script exports the current L1 state from a running geth node
# and merges it with the original genesis configuration to create
# a new genesis file with pre-loaded state (contracts, balances, storage).
#
# This approach allows starting a fresh L1 from block 0 with all contracts
# already deployed, avoiding state restoration issues with consensus clients.

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"
source "${UTILS_DIR}/prerequisites.sh"

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2

# Default values
ENCLAVE_NAME=""
OUTPUT_DIR=""
GETH_SERVICE_NAME="el-1-geth-lighthouse"
FINALIZED_BLOCK=""

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Export L1 state to genesis file for fresh L1 start.

Options:
    --enclave-name NAME    Kurtosis enclave name (required)
    --output-dir DIR       Output directory (required)
    --geth-service NAME    Geth service name (default: el-1-geth-lighthouse)
    --block NUMBER         Block number to export (default: auto-detect finalized)
    -h, --help             Show this help message

Example:
    $0 --enclave-name snapshot --output-dir ./snapshot-output

EOF
    exit 1
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --enclave-name)
                ENCLAVE_NAME="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --geth-service)
                GETH_SERVICE_NAME="$2"
                shift 2
                ;;
            --block)
                FINALIZED_BLOCK="$2"
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
    if [ -z "${ENCLAVE_NAME}" ]; then
        echo "Error: --enclave-name is required" >&2
        usage
    fi

    if [ -z "${OUTPUT_DIR}" ]; then
        echo "Error: --output-dir is required" >&2
        usage
    fi
}

# Get finalized block number
get_finalized_block() {
    local metadata_file="${OUTPUT_DIR}/l1-state/finalized-metadata-artifact/finalized-state.json"

    if [ -f "${metadata_file}" ]; then
        local block=$(jq -r '.finalized_block // 0' "${metadata_file}" 2>/dev/null || echo "0")
        if [ "$block" != "0" ]; then
            echo "$block"
            return 0
        fi
    fi

    # Fallback: query geth directly
    log_info "Querying geth for finalized block..."
    local block=$(kurtosis service exec "${ENCLAVE_NAME}" "${GETH_SERVICE_NAME}" \
        "geth attach --exec 'eth.getBlock(\"finalized\").number' /root/.ethereum/geth.ipc" 2>/dev/null | tail -1 || echo "0")
    echo "$block"
}

# Export state from geth at specified block
export_state() {
    local block_number="$1"
    local output_file="$2"

    log_info "Exporting state from block ${block_number}..."

    # Use debug.dumpBlock to get full state
    # This returns all accounts, balances, code, and storage at the given block
    kurtosis service exec "${ENCLAVE_NAME}" "${GETH_SERVICE_NAME}" \
        "geth attach --exec 'debug.dumpBlock(${block_number})' /root/.ethereum/geth.ipc" \
        > "${output_file}" 2>&1

    if [ $? -eq 0 ] && [ -f "${output_file}" ]; then
        log_success "State exported to ${output_file}"
        local size=$(du -h "${output_file}" | cut -f1)
        log_info "Export size: ${size}"
        return 0
    else
        log_error "Failed to export state"
        return 1
    fi
}

# Download original genesis
download_original_genesis() {
    local genesis_dest="${OUTPUT_DIR}/l1-genesis-original"
    mkdir -p "${genesis_dest}"

    log_info "Downloading original L1 genesis..."
    if kurtosis files download "${ENCLAVE_NAME}" el_cl_genesis_data "${genesis_dest}" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        local genesis_file=$(find "${genesis_dest}" -name "genesis.json" -type f | head -1 || echo "")
        if [ -n "${genesis_file}" ] && [ -f "${genesis_file}" ]; then
            echo "${genesis_file}"
            return 0
        fi
    fi

    log_error "Failed to download original genesis"
    return 1
}

# Merge state dump with original genesis
merge_genesis_with_state() {
    local original_genesis="$1"
    local state_dump="$2"
    local output_genesis="$3"

    log_info "Merging state with original genesis..."

    # Create a script to merge the state
    # The debug.dumpBlock output has accounts in a specific format
    # We need to convert it to genesis alloc format
    python3 <<'PYTHON_SCRIPT' "${original_genesis}" "${state_dump}" "${output_genesis}"
import json
import sys

def convert_state_to_alloc(state_dump):
    """Convert geth debug.dumpBlock output to genesis alloc format"""
    alloc = {}

    # debug.dumpBlock returns accounts with balance, nonce, code, storage
    if 'accounts' in state_dump:
        for address, account_data in state_dump['accounts'].items():
            alloc[address] = {}

            # Add balance if present
            if 'balance' in account_data:
                alloc[address]['balance'] = account_data['balance']

            # Add nonce if present and non-zero
            if 'nonce' in account_data and account_data['nonce'] != 0:
                alloc[address]['nonce'] = str(account_data['nonce'])

            # Add code if present (contract)
            if 'code' in account_data and account_data['code']:
                alloc[address]['code'] = account_data['code']

            # Add storage if present (contract state)
            if 'storage' in account_data and account_data['storage']:
                alloc[address]['storage'] = account_data['storage']

    return alloc

try:
    # Read original genesis
    with open(sys.argv[1], 'r') as f:
        genesis = json.load(f)

    # Read state dump
    with open(sys.argv[2], 'r') as f:
        state_dump = json.load(f)

    # Convert state to alloc format
    new_alloc = convert_state_to_alloc(state_dump)

    # Merge with original genesis (new state overwrites original)
    if 'alloc' not in genesis:
        genesis['alloc'] = {}

    genesis['alloc'].update(new_alloc)

    # Write output genesis
    with open(sys.argv[3], 'w') as f:
        json.dump(genesis, f, indent=2)

    print(f"Genesis merged successfully. Total accounts: {len(genesis['alloc'])}")
    sys.exit(0)

except Exception as e:
    print(f"Error merging genesis: {e}", file=sys.stderr)
    sys.exit(1)

PYTHON_SCRIPT

    if [ $? -eq 0 ]; then
        log_success "Genesis merged successfully"
        return 0
    else
        log_error "Failed to merge genesis"
        return 1
    fi
}

# Main function
main() {
    log_step "1" "L1 Genesis Export"

    # Parse arguments
    parse_args "$@"

    # Setup logging
    setup_logging "${OUTPUT_DIR}" || {
        echo "Error: Failed to setup logging" >&2
        exit ${EXIT_CODE_GENERAL_ERROR}
    }

    # Check prerequisites
    log_section "Checking prerequisites"
    if ! check_kurtosis; then
        log_error "Kurtosis check failed"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi

    if ! command -v python3 &>/dev/null; then
        log_error "python3 is required but not installed"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi

    log_success "Prerequisites check passed"

    # Determine finalized block
    if [ -z "${FINALIZED_BLOCK}" ]; then
        log_section "Detecting finalized block"
        FINALIZED_BLOCK=$(get_finalized_block)
        log_info "Finalized block: ${FINALIZED_BLOCK}"
    fi

    # Create output directory
    mkdir -p "${OUTPUT_DIR}/l1-state"

    # Export state from geth
    log_section "Exporting L1 state"
    local state_dump="${OUTPUT_DIR}/l1-state/state-dump-block-${FINALIZED_BLOCK}.json"
    if ! export_state "${FINALIZED_BLOCK}" "${state_dump}"; then
        log_error "Failed to export state"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi

    # Download original genesis
    log_section "Downloading original genesis"
    local original_genesis=$(download_original_genesis)
    if [ -z "${original_genesis}" ]; then
        log_error "Failed to download original genesis"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi
    log_info "Original genesis: ${original_genesis}"

    # Merge state with genesis
    log_section "Creating genesis with pre-loaded state"
    local output_genesis="${OUTPUT_DIR}/l1-state/genesis.json"
    if ! merge_genesis_with_state "${original_genesis}" "${state_dump}" "${output_genesis}"; then
        log_error "Failed to create genesis"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi

    # Clean up temporary files
    rm -f "${state_dump}"
    rm -rf "${OUTPUT_DIR}/l1-genesis-original"

    # Create metadata
    local genesis_size=$(du -h "${output_genesis}" | cut -f1)
    cat > "${OUTPUT_DIR}/l1-state/genesis-metadata.json" <<EOF
{
    "source_block": ${FINALIZED_BLOCK},
    "genesis_file": "${output_genesis}",
    "file_size": "${genesis_size}",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "enclave": "${ENCLAVE_NAME}"
}
EOF

    log_section "Summary"
    log_info "Genesis file: ${output_genesis}"
    log_info "Source block: ${FINALIZED_BLOCK}"
    log_info "File size: ${genesis_size}"

    log_success "L1 Genesis Export Complete"
}

# Run main function
main "$@"
