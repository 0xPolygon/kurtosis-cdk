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
    
    # Extract geth datadir
    log_section "Extracting geth datadir"
    if extract_datadir "${ENCLAVE_NAME}" "${GETH_SERVICE}" "${GETH_DATADIR}" "${GETH_OUTPUT_DIR}"; then
        log_success "Geth datadir extracted successfully"
    else
        log_error "Failed to extract geth datadir"
        log_error "Service: ${GETH_SERVICE}, Path: ${GETH_DATADIR}"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi
    
    # Validate extracted geth state
    if ! validate_l1_state "${OUTPUT_DIR}/l1-state"; then
        log_warn "Geth state validation warnings (continuing)"
    fi
    
    # Extract lighthouse datadir
    log_section "Extracting lighthouse datadir"
    if extract_datadir "${ENCLAVE_NAME}" "${LIGHTHOUSE_SERVICE}" "${LIGHTHOUSE_DATADIR}" "${LIGHTHOUSE_OUTPUT_DIR}"; then
        log_success "Lighthouse datadir extracted successfully"
    else
        log_error "Failed to extract lighthouse datadir"
        log_error "Service: ${LIGHTHOUSE_SERVICE}, Path: ${LIGHTHOUSE_DATADIR}"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi
    
    # Verify state consistency if RPC URLs are provided
    log_section "Verifying state consistency"
    if [ -n "${L1_RPC_URL}" ]; then
        log_info "Verifying state consistency..."
        
        # Get finalized block from geth state (if possible)
        # Note: This is approximate - we'll use the RPC if available
        local geth_block=0
        local lighthouse_slot=0
        
        if command -v cast &> /dev/null && [ -n "${L1_RPC_URL}" ]; then
            geth_block=$(cast block-number --rpc-url "${L1_RPC_URL}" finalized 2>/dev/null || echo "0")
            log_debug "Finalized block: ${geth_block}"
        fi
        
        if [ -n "${L1_BEACON_URL}" ]; then
            local response
            response=$(curl --silent "${L1_BEACON_URL}/eth/v1/beacon/headers/finalized" 2>/dev/null || echo '{}')
            lighthouse_slot=$(echo "${response}" | jq --raw-output '.data.header.message.slot // 0' 2>/dev/null || echo "0")
            log_debug "Finalized slot: ${lighthouse_slot}"
        fi
        
        if verify_state_consistency "${geth_block}" "${lighthouse_slot}" "${L1_RPC_URL}" "${L1_BEACON_URL}"; then
            log_success "State consistency verified"
        else
            log_warn "State consistency check failed (continuing)"
        fi
    else
        log_info "Skipping state consistency verification (no RPC URLs provided)"
    fi
    
    # Create state manifest
    log_section "Creating state manifest"
    local manifest_file="${OUTPUT_DIR}/l1-state/manifest.json"
    local chain_id=""
    
    # Try to get chain ID from geth state or use default
    if [ -f "${GETH_OUTPUT_DIR}/geth/chaindata/chaindata/CURRENT" ]; then
        # Chain ID might be in the datadir, but it's complex to extract
        # For now, we'll leave it empty and let the user provide it
        chain_id=""
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
