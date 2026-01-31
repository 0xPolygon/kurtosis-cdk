#!/bin/bash
# Alternative L1 state extraction: Extract actual datadirs instead of merging into genesis
# This approach preserves state consistency between geth and lighthouse

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"
source "${UTILS_DIR}/prerequisites.sh"
source "${UTILS_DIR}/state-extractor.sh"

ENCLAVE_NAME=""
OUTPUT_DIR=""
GETH_SERVICE=""
LIGHTHOUSE_SERVICE=""

# Parse arguments (simplified for now)
while [[ $# -gt 0 ]]; do
    case $1 in
        --enclave-name) ENCLAVE_NAME="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --geth-service) GETH_SERVICE="$2"; shift 2 ;;
        --lighthouse-service) LIGHTHOUSE_SERVICE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Main extraction
main() {
    log_step "1" "L1 Datadir Extraction (Alternative Approach)"

    # Setup logging
    setup_logging "${OUTPUT_DIR}"

    # Create output directories
    log_section "Creating output directories"
    GETH_OUTPUT_DIR="${OUTPUT_DIR}/l1-state/geth"
    LIGHTHOUSE_OUTPUT_DIR="${OUTPUT_DIR}/l1-state/lighthouse"
    mkdir -p "${GETH_OUTPUT_DIR}" "${LIGHTHOUSE_OUTPUT_DIR}"

    # Detect service names if not provided
    if [ -z "${GETH_SERVICE}" ] || [ -z "${LIGHTHOUSE_SERVICE}" ]; then
        log_info "Auto-detecting L1 service names..."
        local service_names=$(get_l1_service_names "${ENCLAVE_NAME}")
        GETH_SERVICE=$(echo "${service_names}" | awk '{print $1}')
        LIGHTHOUSE_SERVICE=$(echo "${service_names}" | awk '{print $2}')
    fi

    log_info "Using services: Geth=${GETH_SERVICE}, Lighthouse=${LIGHTHOUSE_SERVICE}"

    # Extract geth datadir (only the geth subdirectory with chaindata)
    log_section "Extracting geth datadir"
    extract_datadir "${ENCLAVE_NAME}" "${GETH_SERVICE}" \
        "/data/geth/execution-data/geth" "${GETH_OUTPUT_DIR}"

    # Extract lighthouse beacon datadir
    log_section "Extracting lighthouse beacon datadir"
    extract_datadir "${ENCLAVE_NAME}" "${LIGHTHOUSE_SERVICE}" \
        "/data/lighthouse/beacon-data/beacon" "${LIGHTHOUSE_OUTPUT_DIR}"

    # Extract lighthouse testnet config
    log_section "Extracting lighthouse testnet configuration"
    LIGHTHOUSE_TESTNET_DIR="${OUTPUT_DIR}/l1-state/lighthouse-testnet"
    mkdir -p "${LIGHTHOUSE_TESTNET_DIR}"

    if kurtosis files download "${ENCLAVE_NAME}" el_cl_genesis_data "${LIGHTHOUSE_TESTNET_DIR}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Testnet configuration extracted"
    else
        log_error "Failed to extract testnet configuration"
        exit 1
    fi

    # Extract validator keys
    log_section "Extracting validator keystores"
    VALIDATOR_KEYS_DIR="${OUTPUT_DIR}/l1-state/validator-keys"
    mkdir -p "${VALIDATOR_KEYS_DIR}"

    if kurtosis files download "${ENCLAVE_NAME}" l1-validator-keys "${VALIDATOR_KEYS_DIR}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Validator keys extracted"
    else
        log_warn "Failed to extract validator keys"
    fi

    # Export execution genesis for reference
    log_section "Exporting execution genesis"
    kurtosis files download "${ENCLAVE_NAME}" el_cl_genesis_data "${OUTPUT_DIR}/l1-state/" 2>&1 | tee -a "${LOG_FILE}"
    find "${OUTPUT_DIR}/l1-state" -name "genesis.json" -exec mv {} "${OUTPUT_DIR}/l1-state/genesis.json" \; 2>/dev/null || true

    # Create manifest
    cat > "${OUTPUT_DIR}/l1-state/manifest.json" <<EOF
{
    "extraction_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "enclave_name": "${ENCLAVE_NAME}",
    "extraction_method": "datadir",
    "note": "Extracted actual datadirs from running services for state consistency"
}
EOF

    log_success "L1 Datadir Extraction Complete"
}

main "$@"
