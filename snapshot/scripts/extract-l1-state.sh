#!/bin/bash
# Extract L1 state from Kurtosis enclave after snapshot run completes
#
# This script extracts geth and lighthouse datadirs from stopped services
# and verifies state consistency.

set -euo pipefail

# Default values
ENCLAVE_NAME=""
OUTPUT_DIR=""
L1_RPC_URL=""
L1_BEACON_URL=""
GETH_SERVICE=""
LIGHTHOUSE_SERVICE=""
GETH_DATADIR="/root/.ethereum"
LIGHTHOUSE_DATADIR="/root/.lighthouse"
# Note: These are the target paths in the Docker image, not the Kurtosis extraction paths

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"
source "${UTILS_DIR}/prerequisites.sh"
source "${UTILS_DIR}/validation.sh"
source "${UTILS_DIR}/state-extractor.sh"

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2
EXIT_CODE_PREREQ_ERROR=3

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Extract L1 state from Kurtosis enclave for snapshot creation.

Options:
    --enclave-name NAME       Kurtosis enclave name (required)
    --output-dir DIR          Output directory for extracted state (required)
    --l1-rpc-url URL          L1 RPC URL (optional, for verification)
    --l1-beacon-url URL       L1 beacon API URL (optional, for verification)
    --geth-service NAME       Geth service name (optional, auto-detected if not provided)
    --lighthouse-service NAME Lighthouse service name (optional, auto-detected if not provided)
    --geth-datadir PATH       Geth datadir path (default: /root/.ethereum)
    --lighthouse-datadir PATH Lighthouse datadir path (default: /root/.lighthouse)
    -h, --help                Show this help message

Example:
    $0 \\
        --enclave-name snapshot \\
        --output-dir ./snapshot-output \\
        --l1-rpc-url http://el-1-geth-lighthouse:8545 \\
        --l1-beacon-url http://cl-1-lighthouse-geth:4000
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
            --l1-rpc-url)
                L1_RPC_URL="$2"
                shift 2
                ;;
            --l1-beacon-url)
                L1_BEACON_URL="$2"
                shift 2
                ;;
            --geth-service)
                GETH_SERVICE="$2"
                shift 2
                ;;
            --lighthouse-service)
                LIGHTHOUSE_SERVICE="$2"
                shift 2
                ;;
            --geth-datadir)
                GETH_DATADIR="$2"
                shift 2
                ;;
            --lighthouse-datadir)
                LIGHTHOUSE_DATADIR="$2"
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

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ ${exit_code} -ne 0 ]; then
        log_error "Script failed with exit code ${exit_code}"
        log_error "Check log file for details: ${LOG_FILE}"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main extraction function
main() {
    log_step "1" "L1 State Extraction for Snapshot"
    
    # Parse arguments
    parse_args "$@"
    
    # Setup logging
    setup_logging "${OUTPUT_DIR}" || {
        echo "Error: Failed to setup logging" >&2
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    
    # Check prerequisites
    log_section "Checking prerequisites"
    if ! check_kurtosis_cli; then
        log_error "Prerequisites check failed"
        exit ${EXIT_CODE_PREREQ_ERROR}
    fi
    
    if ! check_enclave_exists "${ENCLAVE_NAME}"; then
        log_error "Enclave check failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    if ! check_output_dir "${OUTPUT_DIR}"; then
        log_error "Output directory check failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    log_success "Prerequisites check passed"
    
    # Create output directories
    log_section "Creating output directories"
    GETH_OUTPUT_DIR="${OUTPUT_DIR}/l1-state/geth"
    LIGHTHOUSE_OUTPUT_DIR="${OUTPUT_DIR}/l1-state/lighthouse"
    mkdir -p "${GETH_OUTPUT_DIR}" || {
        log_error "Failed to create geth output directory"
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    mkdir -p "${LIGHTHOUSE_OUTPUT_DIR}" || {
        log_error "Failed to create lighthouse output directory"
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    log_success "Output directories created"
    
    # Auto-detect service names if not provided
    log_section "Detecting L1 service names"
    if [ -z "${GETH_SERVICE}" ] || [ -z "${LIGHTHOUSE_SERVICE}" ]; then
        log_info "Auto-detecting L1 service names..."
        local service_names
        service_names=$(get_l1_service_names "${ENCLAVE_NAME}") || {
            log_error "Failed to detect L1 service names"
            exit ${EXIT_CODE_GENERAL_ERROR}
        }
        if [ -z "${GETH_SERVICE}" ]; then
            GETH_SERVICE=$(echo "${service_names}" | awk '{print $1}')
        fi
        if [ -z "${LIGHTHOUSE_SERVICE}" ]; then
            LIGHTHOUSE_SERVICE=$(echo "${service_names}" | awk '{print $2}')
        fi
    fi
    
    log_info "Using services:"
    log_info "  Geth: ${GETH_SERVICE}"
    log_info "  Lighthouse: ${LIGHTHOUSE_SERVICE}"
    
    # Export L1 state to genesis file from running geth
    # This approach creates a fresh genesis with pre-loaded state (contracts, balances, storage)
    # allowing L1 to start from block 0 without state restoration issues
    log_section "Exporting L1 state to genesis file"

    log_info "Exporting state from finalized block..."

    # Get deployment block (latest block after contract deployment)
    local deployment_block=0
    local deployment_metadata_dir="${OUTPUT_DIR}/l1-state/deployment-metadata-artifact-temp"
    rm -rf "${deployment_metadata_dir}"

    if kurtosis files download "${ENCLAVE_NAME}" deployment-block-metadata "${deployment_metadata_dir}" 2>&1 | tee -a "${LOG_FILE}"; then
        local deployment_file="${deployment_metadata_dir}/deployment-block.json"
        if [ -f "${deployment_file}" ]; then
            deployment_block=$(jq -r '.deployment_block // 0' "${deployment_file}" 2>/dev/null || echo "0")
            log_info "Deployment block from metadata: ${deployment_block}"
        fi
        rm -rf "${deployment_metadata_dir}"
    fi

    # Get finalized block number
    local finalized_block=0
    local metadata_artifact_dir="${OUTPUT_DIR}/l1-state/finalized-metadata-artifact-temp"
    rm -rf "${metadata_artifact_dir}"

    if kurtosis files download "${ENCLAVE_NAME}" l1-finalized-metadata "${metadata_artifact_dir}" 2>&1 | tee -a "${LOG_FILE}"; then
        local metadata_file="${metadata_artifact_dir}/finalized-state.json"
        if [ -f "${metadata_file}" ]; then
            finalized_block=$(jq -r '.finalized_block // 0' "${metadata_file}" 2>/dev/null || echo "0")
            log_info "Finalized block from metadata: ${finalized_block}"
        fi
        rm -rf "${metadata_artifact_dir}"
    fi

    # Fallback: query geth directly if metadata not available
    if [ "${finalized_block}" = "0" ]; then
        log_info "Querying geth for finalized block..."
        finalized_block=$(kurtosis service exec "${ENCLAVE_NAME}" "${GETH_SERVICE}" \
            "geth attach --exec 'eth.getBlock(\"finalized\").number' /data/geth/execution-data/geth.ipc" 2>/dev/null | grep -o '[0-9]*' | head -1 || echo "0")
        log_info "Finalized block from geth: ${finalized_block}"
    fi

    # Verify finalized block includes deployment block
    if [ "${deployment_block}" -gt 0 ] && [ "${finalized_block}" -lt "${deployment_block}" ]; then
        log_error "Finalized block ($finalized_block) is before deployment block ($deployment_block)!"
        log_error "This means OP Stack contracts are not finalized yet."
        log_error "Increase --l1-wait-blocks parameter or wait longer before taking snapshot."
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi

    if [ "${deployment_block}" -gt 0 ]; then
        log_success "Verified: finalized block ($finalized_block) >= deployment block ($deployment_block)"
    fi

    # Export state using debug.dumpBlock
    log_info "Exporting state from block ${finalized_block}..."
    local state_dump="${OUTPUT_DIR}/l1-state/state-dump.json"

    kurtosis service exec "${ENCLAVE_NAME}" "${GETH_SERVICE}" \
        "geth attach --exec 'JSON.stringify(debug.dumpBlock(${finalized_block}))' /data/geth/execution-data/geth.ipc" \
        > "${state_dump}" 2>&1

    if [ -f "${state_dump}" ] && [ -s "${state_dump}" ]; then
        log_success "State exported successfully"
        local size=$(du -h "${state_dump}" | cut -f1)
        log_info "State dump size: ${size}"
    else
        log_error "Failed to export state from geth"
        cat "${state_dump}" 2>&1 | tee -a "${LOG_FILE}" || true
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi

    # Download original genesis
    log_info "Downloading original genesis configuration..."
    local genesis_artifact_dir="${OUTPUT_DIR}/l1-genesis-original"
    rm -rf "${genesis_artifact_dir}"
    mkdir -p "${genesis_artifact_dir}"

    if ! kurtosis files download "${ENCLAVE_NAME}" el_cl_genesis_data "${genesis_artifact_dir}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Failed to download original genesis"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi

    local original_genesis=$(find "${genesis_artifact_dir}" -name "genesis.json" -type f | head -1)
    if [ -z "${original_genesis}" ] || [ ! -f "${original_genesis}" ]; then
        log_error "Genesis file not found in artifact"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi
    log_info "Original genesis: ${original_genesis}"

    # Merge state with genesis using Python
    log_info "Merging exported state with genesis..."
    local output_genesis="${OUTPUT_DIR}/l1-state/genesis.json"

    python3 - "${original_genesis}" "${state_dump}" "${output_genesis}" <<'PYTHON_EOF'
import json
import sys

def convert_state_to_alloc(state_dump):
    """Convert geth debug.dumpBlock output to genesis alloc format"""
    alloc = {}
    accounts = state_dump.get('accounts', {})

    for address, account_data in accounts.items():
        # Normalize address format
        addr = address.lower() if not address.startswith('0x') else address[2:].lower()
        addr = '0x' + addr

        alloc[addr] = {}

        # Add balance
        if 'balance' in account_data and account_data['balance']:
            alloc[addr]['balance'] = account_data['balance']

        # Add nonce if non-zero
        if 'nonce' in account_data and account_data['nonce'] != 0:
            alloc[addr]['nonce'] = hex(account_data['nonce'])

        # Add code for contracts
        if 'code' in account_data and account_data['code']:
            alloc[addr]['code'] = account_data['code']

        # Add storage for contracts
        if 'storage' in account_data and account_data['storage']:
            alloc[addr]['storage'] = account_data['storage']

    return alloc

try:
    # Read files
    with open(sys.argv[1], 'r') as f:
        genesis = json.load(f)

    with open(sys.argv[2], 'r') as f:
        lines = f.readlines()
        # Skip Kurtosis wrapper lines and find the JSON line
        state_data = None
        for line in lines:
            stripped = line.strip()
            if stripped and not stripped.startswith('The command') and not stripped.startswith('Error:'):
                state_data = stripped
                break

        if not state_data:
            print("❌ Error: No valid JSON found in state dump", file=sys.stderr)
            sys.exit(1)

        # Handle JSON string wrapping (geth returns JSON.stringify output)
        if state_data.startswith('"') and state_data.endswith('"'):
            # Remove outer quotes and unescape
            state_data = json.loads(state_data)

        state_dump = json.loads(state_data) if isinstance(state_data, str) else state_data

    # Convert and merge
    new_alloc = convert_state_to_alloc(state_dump)

    if 'alloc' not in genesis:
        genesis['alloc'] = {}

    genesis['alloc'].update(new_alloc)

    # Write output
    with open(sys.argv[3], 'w') as f:
        json.dump(genesis, f, indent=2)

    print(f"✅ Genesis created with {len(genesis['alloc'])} accounts", file=sys.stderr)
    sys.exit(0)

except Exception as e:
    print(f"❌ Error: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

    if [ $? -eq 0 ] && [ -f "${output_genesis}" ]; then
        log_success "Genesis file created with pre-loaded state"
        local genesis_size=$(du -h "${output_genesis}" | cut -f1)
        log_info "Genesis file size: ${genesis_size}"

        # Clean up temporary files
        rm -f "${state_dump}"
        rm -rf "${genesis_artifact_dir}"
    else
        log_error "Failed to create genesis file"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi

    # Note: No need to extract geth or lighthouse datadirs
    # Both will start fresh from genesis (block 0, slot 0)
    log_info "Geth and Lighthouse will start fresh from genesis (no datadir extraction needed)"

    # Extract lighthouse testnet configuration (genesis.ssz, config.yaml, etc.)
    log_section "Extracting lighthouse testnet configuration from artifacts"

    # Create testnet directory
    LIGHTHOUSE_TESTNET_DIR="${OUTPUT_DIR}/l1-state/lighthouse-testnet"
    mkdir -p "${LIGHTHOUSE_TESTNET_DIR}"

    # Clean up any existing artifact directories from previous runs
    rm -rf "${OUTPUT_DIR}/l1-state/el-cl-genesis-artifact"

    # Download the el_cl_genesis_data artifact which contains the INITIAL genesis files
    # This is preferred over l1-lighthouse-testnet because it has the genesis from slot 0
    log_info "Downloading el_cl_genesis_data artifact (initial genesis files)..."
    if kurtosis files download "${ENCLAVE_NAME}" el_cl_genesis_data "${OUTPUT_DIR}/l1-state/el-cl-genesis-artifact" 2>&1 | tee -a "${LOG_FILE}"; then
        if [ -d "${OUTPUT_DIR}/l1-state/el-cl-genesis-artifact" ]; then
            # Move all genesis files to testnet directory
            mv "${OUTPUT_DIR}/l1-state/el-cl-genesis-artifact"/* "${LIGHTHOUSE_TESTNET_DIR}/" 2>/dev/null || true
            rm -rf "${OUTPUT_DIR}/l1-state/el-cl-genesis-artifact"
            log_success "Genesis files extracted from el_cl_genesis_data artifact"

            # Verify critical files exist
            if [ -f "${LIGHTHOUSE_TESTNET_DIR}/genesis.ssz" ] && [ -f "${LIGHTHOUSE_TESTNET_DIR}/config.yaml" ]; then
                log_success "Found genesis.ssz and config.yaml in testnet directory"

                # NOTE: Do NOT overwrite l1-state/genesis.json here!
                # That file contains the merged genesis with deployed OP Stack contracts.
                # The genesis.json from el_cl_genesis_data is the ORIGINAL genesis without deployed contracts.
                log_info "Keeping merged execution genesis.json (includes deployed contracts)"
            else
                log_warn "Genesis files may be missing from el_cl_genesis_data artifact"
                log_info "Testnet directory contents: $(ls -la ${LIGHTHOUSE_TESTNET_DIR}/ 2>&1 || echo 'empty')"
            fi
        else
            log_warn "el_cl_genesis_data artifact directory not found"
        fi
    else
        log_warn "Failed to download el_cl_genesis_data artifact"
        log_warn "Trying fallback to l1-lighthouse-testnet artifact..."

        # Fallback to l1-lighthouse-testnet if el_cl_genesis_data is not available
        rm -rf "${OUTPUT_DIR}/l1-state/lighthouse-testnet-artifact"
        if kurtosis files download "${ENCLAVE_NAME}" l1-lighthouse-testnet "${OUTPUT_DIR}/l1-state/lighthouse-testnet-artifact" 2>&1 | tee -a "${LOG_FILE}"; then
            if [ -d "${OUTPUT_DIR}/l1-state/lighthouse-testnet-artifact" ]; then
                mv "${OUTPUT_DIR}/l1-state/lighthouse-testnet-artifact"/* "${LIGHTHOUSE_TESTNET_DIR}/" 2>/dev/null || true
                rm -rf "${OUTPUT_DIR}/l1-state/lighthouse-testnet-artifact"
                log_warn "Using l1-lighthouse-testnet artifact (may not match execution genesis)"
            fi
        fi
    fi

    # Fix permissions on testnet directory
    if command -v docker &>/dev/null && [ -d "${LIGHTHOUSE_TESTNET_DIR}" ]; then
        docker run --rm -v "${LIGHTHOUSE_TESTNET_DIR}:/data" -w /data alpine:latest sh -c "chmod -R a+rX /data" 2>&1 | tee -a "${LOG_FILE}" || {
            log_warn "Failed to fix testnet permissions"
        }
    fi

    # Extract validator keystores
    log_section "Extracting validator keystores from artifacts"

    # Create validator keys directory
    VALIDATOR_KEYS_DIR="${OUTPUT_DIR}/l1-state/validator-keys"
    mkdir -p "${VALIDATOR_KEYS_DIR}"

    # Clean up any existing artifact directories from previous runs
    rm -rf "${OUTPUT_DIR}/l1-state/validator-keys-artifact"

    log_info "Downloading l1-validator-keys artifact..."
    if kurtosis files download "${ENCLAVE_NAME}" l1-validator-keys "${OUTPUT_DIR}/l1-state/validator-keys-artifact" 2>&1 | tee -a "${LOG_FILE}"; then
        # Move the extracted validator keys to the expected location
        if [ -d "${OUTPUT_DIR}/l1-state/validator-keys-artifact" ]; then
            # Move all validator files (keystores, secrets, validator_definitions.yml)
            mv "${OUTPUT_DIR}/l1-state/validator-keys-artifact"/* "${VALIDATOR_KEYS_DIR}/" 2>/dev/null || true
            rm -rf "${OUTPUT_DIR}/l1-state/validator-keys-artifact"
            log_success "Validator keys extracted successfully"

            # Verify critical files exist
            if [ -f "${VALIDATOR_KEYS_DIR}/validator_definitions.yml" ]; then
                log_success "Found validator_definitions.yml"
                local num_validators=$(grep -c "enabled: true" "${VALIDATOR_KEYS_DIR}/validator_definitions.yml" 2>/dev/null || echo "0")
                log_info "Number of validators: ${num_validators}"
            else
                log_warn "validator_definitions.yml not found (continuing anyway)"
            fi
        else
            log_warn "Validator keys artifact directory not found (continuing anyway)"
        fi
    else
        log_warn "Failed to download validator keys artifact"
        log_warn "Validator service will not be able to propose blocks without keys"
    fi

    # Fix permissions on validator keys directory
    if command -v docker &>/dev/null && [ -d "${VALIDATOR_KEYS_DIR}" ]; then
        docker run --rm -v "${VALIDATOR_KEYS_DIR}:/data" -w /data alpine:latest sh -c "chmod -R a+rX /data" 2>&1 | tee -a "${LOG_FILE}" || {
            log_warn "Failed to fix validator keys permissions"
        }
    fi

    # Get finalized block/slot information
    log_section "Getting finalized block information"
    local geth_block=0
    local lighthouse_slot=0

    # Try to extract finalized state metadata from Kurtosis artifact
    log_info "Attempting to read finalized state from Kurtosis artifact..."
    local metadata_artifact_dir="${OUTPUT_DIR}/l1-state/finalized-metadata-artifact"
    rm -rf "${metadata_artifact_dir}"

    if kurtosis files download "${ENCLAVE_NAME}" l1-finalized-metadata "${metadata_artifact_dir}" 2>&1 | tee -a "${LOG_FILE}"; then
        local metadata_file="${metadata_artifact_dir}/finalized-state.json"
        if [ -f "${metadata_file}" ]; then
            log_success "Found finalized state metadata artifact"
            geth_block=$(jq -r '.finalized_block // 0' "${metadata_file}" 2>/dev/null || echo "0")
            lighthouse_slot=$(jq -r '.finalized_slot // 0' "${metadata_file}" 2>/dev/null || echo "0")

            # Also extract RPC URLs if they weren't provided
            if [ -z "${L1_RPC_URL}" ]; then
                L1_RPC_URL=$(jq -r '.l1_rpc_url // ""' "${metadata_file}" 2>/dev/null || echo "")
            fi
            if [ -z "${L1_BEACON_URL}" ]; then
                L1_BEACON_URL=$(jq -r '.l1_beacon_url // ""' "${metadata_file}" 2>/dev/null || echo "")
            fi

            log_info "Finalized block: ${geth_block}"
            log_info "Finalized slot: ${lighthouse_slot}"
            rm -rf "${metadata_artifact_dir}"
        else
            log_warn "Finalized state metadata file not found in artifact"
        fi
    else
        log_warn "Could not download finalized state metadata artifact (may not exist)"
    fi

    # Fallback: Query RPC if we still don't have finalized block and RPC URLs are available
    if [ "${geth_block}" = "0" ] && [ -n "${L1_RPC_URL}" ]; then
        log_info "Querying RPC for finalized block..."
        if command -v cast &> /dev/null; then
            geth_block=$(cast block-number --rpc-url "${L1_RPC_URL}" finalized 2>/dev/null || echo "0")
            log_info "Finalized block from RPC: ${geth_block}"
        else
            log_warn "cast command not available, cannot query finalized block"
        fi
    fi

    if [ "${lighthouse_slot}" = "0" ] && [ -n "${L1_BEACON_URL}" ]; then
        log_info "Querying beacon API for finalized slot..."
        local response
        response=$(curl --silent "${L1_BEACON_URL}/eth/v1/beacon/headers/finalized" 2>/dev/null || echo '{}')
        lighthouse_slot=$(echo "${response}" | jq --raw-output '.data.header.message.slot // 0' 2>/dev/null || echo "0")
        log_info "Finalized slot from beacon: ${lighthouse_slot}"
    fi

    # Verify state consistency if we have the data
    if [ "${geth_block}" != "0" ] || [ "${lighthouse_slot}" != "0" ]; then
        log_section "Verifying state consistency"
        if verify_state_consistency "${geth_block}" "${lighthouse_slot}" "${L1_RPC_URL}" "${L1_BEACON_URL}"; then
            log_success "State consistency verified"
        else
            log_warn "State consistency check failed (continuing)"
        fi
    else
        log_warn "No finalized block/slot information available - snapshot may be incomplete"
    fi
    
    # Create state manifest
    log_section "Creating state manifest"
    local manifest_file="${OUTPUT_DIR}/l1-state/manifest.json"
    local chain_id="271828"  # Default L1 chain ID

    # Try to get chain ID from Kurtosis args if available
    if [ -f "${OUTPUT_DIR}/kurtosis-args.json" ]; then
        local extracted_chain_id
        extracted_chain_id=$(jq -r '.args.l1_chain_id // empty' "${OUTPUT_DIR}/kurtosis-args.json" 2>/dev/null || echo "")
        if [ -n "${extracted_chain_id}" ]; then
            chain_id="${extracted_chain_id}"
        fi
    fi
    
    # Create manifest JSON
    if ! cat > "${manifest_file}" <<EOF
{
    "extraction_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "enclave_name": "${ENCLAVE_NAME}",
    "geth": {
        "service_name": "${GETH_SERVICE}",
        "datadir_path": "${GETH_DATADIR}",
        "extracted_path": "${GETH_OUTPUT_DIR}",
        "finalized_block": ${geth_block:-0}
    },
    "lighthouse": {
        "service_name": "${LIGHTHOUSE_SERVICE}",
        "datadir_path": "${LIGHTHOUSE_DATADIR}",
        "extracted_path": "${LIGHTHOUSE_OUTPUT_DIR}",
        "finalized_slot": ${lighthouse_slot:-0}
    },
    "chain_id": "${chain_id}",
    "l1_rpc_url": "${L1_RPC_URL}",
    "l1_beacon_url": "${L1_BEACON_URL}"
}
EOF
    then
        log_error "Failed to create state manifest"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi
    
    # Validate manifest JSON
    if validate_config_file "${manifest_file}" "json"; then
        log_success "State manifest created: ${manifest_file}"
    else
        log_error "State manifest validation failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    # Print summary
    log_section "Summary"
    log_info "Output directory: ${OUTPUT_DIR}/l1-state"
    log_info "  Geth: ${GETH_OUTPUT_DIR}"
    log_info "  Lighthouse: ${LIGHTHOUSE_OUTPUT_DIR}"
    log_info "  Manifest: ${manifest_file}"
    
    if [ -n "${L1_RPC_URL}" ]; then
        log_info "Finalized state:"
        log_info "  Block: ${geth_block:-0}"
        log_info "  Slot: ${lighthouse_slot:-0}"
    fi
    
    log_success "L1 State Extraction Complete"
}

# Run main function
main "$@"
