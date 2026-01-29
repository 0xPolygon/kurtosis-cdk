#!/bin/bash
# User-facing entry point for snapshot creation
#
# This script orchestrates the complete snapshot creation process:
# 1. Generates args file with snapshot_mode enabled
# 2. Runs kurtosis run with snapshot mode
# 3. Calls post-processing scripts in sequence:
#    - extract-l1-state.sh
#    - process-configs.sh
#    - build-l1-images.sh
#    - generate-compose.sh
# 4. Validates output and creates summary report

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source utility functions
source "${UTILS_DIR}/logging.sh"
source "${UTILS_DIR}/prerequisites.sh"
source "${UTILS_DIR}/validation.sh"

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2
EXIT_CODE_PREREQ_ERROR=3
EXIT_CODE_KURTOSIS_ERROR=4

# Default values
ENCLAVE_NAME=""
OUTPUT_DIR=""
NETWORKS_JSON=""
L1_WAIT_BLOCKS=10
KURTOSIS_ARGS_FILE=""
CLEANUP_ENCLAVE=false
SKIP_KURTOSIS=false
SKIP_VERIFICATION=false
VERIFY_RUNTIME=false

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Create a snapshot of a Kurtosis environment for docker-compose deployment.

This script:
1. Generates a Kurtosis args file with snapshot_mode enabled
2. Runs kurtosis run to deploy L1, register networks, and extract configs
3. Extracts L1 state from the enclave
4. Processes config artifacts to static format
5. Builds Docker images with L1 state
6. Generates docker-compose.yml

Options:
    --enclave-name NAME       Kurtosis enclave name (required)
    --output-dir DIR          Output directory for snapshot (required)
    --networks FILE           JSON file with network configs (optional, see below)
    --l1-wait-blocks N        Number of blocks to wait for L1 finalization (default: 10)
    --args-file FILE          Pre-generated args file (optional, will generate if not provided)
    --cleanup-enclave         Clean up enclave after snapshot (default: false)
    --skip-kurtosis           Skip kurtosis run (for testing post-processing only)
    --skip-verification       Skip snapshot verification (default: false)
    --verify-runtime          Run runtime verification (starts docker-compose) (default: false)
    -h, --help                Show this help message

Network Configuration:
    If --networks is not provided, you must provide a valid args file with snapshot_networks.
    The networks JSON file should have the following structure:
    
    {
      "networks": [
        {
          "sequencer_type": "cdk-erigon",
          "consensus_type": "rollup",
          "deployment_suffix": "-001",
          "l2_chain_id": 20201,
          "network_id": 1,
          "l2_sequencer_address": "0x...",
          "l2_sequencer_private_key": "0x...",
          ...
        }
      ]
    }
    
    See snapshot.md for complete network configuration format.

Example:
    $0 \\
        --enclave-name snapshot \\
        --output-dir ./snapshot-output \\
        --networks ./networks.json \\
        --l1-wait-blocks 10

    $0 \\
        --enclave-name snapshot \\
        --output-dir ./snapshot-output \\
        --args-file ./snapshot-args.json
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
            --networks)
                NETWORKS_JSON="$2"
                shift 2
                ;;
            --l1-wait-blocks)
                L1_WAIT_BLOCKS="$2"
                shift 2
                ;;
            --args-file)
                KURTOSIS_ARGS_FILE="$2"
                shift 2
                ;;
            --cleanup-enclave)
                CLEANUP_ENCLAVE=true
                shift
                ;;
            --skip-kurtosis)
                SKIP_KURTOSIS=true
                shift
                ;;
            --skip-verification)
                SKIP_VERIFICATION=true
                shift
                ;;
            --verify-runtime)
                VERIFY_RUNTIME=true
                shift
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

# Generate Kurtosis args file
generate_args_file() {
    local args_file="$1"
    local networks_file="$2"
    
    log_section "Generating Kurtosis args file"
    
    # Start with base structure (Kurtosis expects deployment_stages and args at top level)
    local args_json="{"
    
    # Add deployment stages (minimal for snapshot mode)
    args_json+="\"deployment_stages\": {"
    args_json+="\"deploy_l1\": true,"
    args_json+="\"deploy_agglayer_contracts_on_l1\": true,"
    args_json+="\"deploy_databases\": false,"
    args_json+="\"deploy_cdk_central_environment\": false,"
    args_json+="\"deploy_cdk_bridge_infra\": false,"
    args_json+="\"deploy_agglayer\": false,"
    args_json+="\"deploy_op_succinct\": false,"
    args_json+="\"deploy_l2_contracts\": false,"
    args_json+="\"deploy_aggkit_node\": false"
    args_json+="},"
    
    # Start args section
    args_json+="\"args\": {"
    args_json+="\"snapshot_mode\": true,"
    args_json+="\"snapshot_output_dir\": \"${OUTPUT_DIR}\","
    args_json+="\"snapshot_l1_wait_blocks\": ${L1_WAIT_BLOCKS},"
    
    # Add snapshot_networks from JSON file
    if [ -n "${networks_file}" ] && [ -f "${networks_file}" ]; then
        log_info "Reading networks from: ${networks_file}"
        
        # Validate JSON file
        if ! jq empty "${networks_file}" 2>/dev/null; then
            log_error "Invalid JSON file: ${networks_file}"
            return 1
        fi
        
        # Extract networks array
        local networks_array
        networks_array=$(jq -c '.networks // .' "${networks_file}" 2>/dev/null)
        if [ -z "${networks_array}" ]; then
            log_error "No networks found in ${networks_file}"
            return 1
        fi
        
        # Add networks to args
        args_json+="\"snapshot_networks\": ${networks_array}"
        log_info "Loaded $(echo "${networks_array}" | jq 'length') network(s)"
    else
        log_error "Networks file not provided or not found: ${networks_file}"
        return 1
    fi
    
    # Close args section
    args_json+="}"
    
    # Close top-level JSON
    args_json+="}"
    
    # Write args file
    local temp_file
    temp_file=$(mktemp)
    echo "${args_json}" | jq '.' > "${temp_file}" || {
        log_error "Failed to format JSON"
        rm -f "${temp_file}"
        return 1
    }
    
    # Validate generated JSON
    if ! jq empty "${temp_file}" 2>/dev/null; then
        log_error "Generated invalid JSON"
        rm -f "${temp_file}"
        return 1
    fi
    
    mv "${temp_file}" "${args_file}"
    log_success "Args file generated: ${args_file}"
    
    # Show preview
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        log_debug "Args file contents:"
        jq '.' "${args_file}" | head -20
    fi
}

# Run Kurtosis
run_kurtosis() {
    local enclave_name="$1"
    local args_file="$2"
    
    log_section "Running Kurtosis"
    
    log_info "Enclave: ${enclave_name}"
    log_info "Args file: ${args_file}"
    
    # Check if enclave already exists
    if kurtosis enclave inspect "${enclave_name}" &>/dev/null; then
        log_warn "Enclave '${enclave_name}' already exists"
        log_info "You may want to clean it up first: kurtosis enclave rm ${enclave_name}"
    fi
    
    # Run kurtosis
    log_info "Starting kurtosis run (this may take several minutes)..."
    if kurtosis run --enclave "${enclave_name}" --args-file "${args_file}" "${PROJECT_ROOT}"; then
        log_success "Kurtosis run completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Kurtosis run failed with exit code ${exit_code}"
        log_error "Check kurtosis logs for details"
        return ${exit_code}
    fi
}

# Run post-processing scripts
run_post_processing() {
    local enclave_name="$1"
    local output_dir="$2"
    local networks_file="$3"
    
    log_section "Running Post-Processing Scripts"
    
    # Step 1: Extract L1 state
    log_step "1" "Extracting L1 State"
    if ! "${SCRIPT_DIR}/extract-l1-state.sh" \
        --enclave-name "${enclave_name}" \
        --output-dir "${output_dir}"; then
        log_error "L1 state extraction failed"
        return 1
    fi

    # Step 2: Extract L2 contract addresses
    log_step "2" "Extracting L2 Contract Addresses"
    if ! "${SCRIPT_DIR}/extract-l2-contracts.sh" \
        "${enclave_name}" \
        "${output_dir}"; then
        log_warn "L2 contract extraction failed (continuing anyway)"
    fi

    # Step 3: Process configs
    log_step "3" "Processing Configs"
    if [ -n "${networks_file}" ] && [ -f "${networks_file}" ]; then
        if ! "${SCRIPT_DIR}/process-configs.sh" \
            --enclave-name "${enclave_name}" \
            --output-dir "${output_dir}" \
            --networks-json "${networks_file}"; then
            log_error "Config processing failed"
            return 1
        fi
    else
        if ! "${SCRIPT_DIR}/process-configs.sh" \
            --enclave-name "${enclave_name}" \
            --output-dir "${output_dir}"; then
            log_error "Config processing failed"
            return 1
        fi
    fi
    
    # Step 4: Build L1 images
    log_step "4" "Building L1 Docker Images"
    if ! "${SCRIPT_DIR}/build-l1-images.sh" \
        --output-dir "${output_dir}"; then
        log_error "L1 image building failed"
        return 1
    fi
    
    # Step 5: Generate docker-compose
    log_step "5" "Generating Docker Compose"
    if ! "${SCRIPT_DIR}/generate-compose.sh" \
        --output-dir "${output_dir}"; then
        log_error "Docker compose generation failed"
        return 1
    fi
    
    log_success "All post-processing steps completed"
    return 0
}

# Validate snapshot output
validate_output() {
    local output_dir="$1"
    
    log_section "Validating Snapshot Output"
    
    local errors=0
    
    # Check required directories
    local required_dirs=(
        "${output_dir}/l1-state"
        "${output_dir}/l1-state/geth"
        "${output_dir}/l1-state/lighthouse"
        "${output_dir}/configs"
        "${output_dir}/l1-images"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "${dir}" ]; then
            log_error "Missing required directory: ${dir}"
            errors=$((errors + 1))
        fi
    done
    
    # Check required files
    local required_files=(
        "${output_dir}/l1-state/manifest.json"
        "${output_dir}/docker-compose.yml"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "${file}" ]; then
            log_error "Missing required file: ${file}"
            errors=$((errors + 1))
        fi
    done
    
    # Check docker-compose syntax
    if [ -f "${output_dir}/docker-compose.yml" ]; then
        if command -v docker-compose &>/dev/null; then
            if ! docker-compose -f "${output_dir}/docker-compose.yml" config &>/dev/null; then
                log_error "docker-compose.yml has syntax errors"
                errors=$((errors + 1))
            fi
        elif docker compose version &>/dev/null; then
            if ! docker compose -f "${output_dir}/docker-compose.yml" config &>/dev/null; then
                log_error "docker-compose.yml has syntax errors"
                errors=$((errors + 1))
            fi
        fi
    fi
    
    if [ ${errors} -gt 0 ]; then
        log_error "Validation failed: ${errors} error(s)"
        return 1
    fi
    
    log_success "Snapshot output validation passed"
    return 0
}

# Create summary report
create_summary() {
    local output_dir="$1"
    local summary_file="${output_dir}/snapshot-summary.json"
    
    log_section "Creating Summary Report"
    
    # Gather information
    local l1_manifest="${output_dir}/l1-state/manifest.json"
    local networks_count=0
    local networks_info="[]"
    
    # Count networks from configs directory
    if [ -d "${output_dir}/configs" ]; then
        networks_count=$(find "${output_dir}/configs" -mindepth 1 -maxdepth 1 -type d | wc -l)
    fi
    
    # Get L1 state info
    local geth_block=0
    local lighthouse_slot=0
    if [ -f "${l1_manifest}" ]; then
        geth_block=$(jq -r '.geth.finalized_block // 0' "${l1_manifest}" 2>/dev/null || echo "0")
        lighthouse_slot=$(jq -r '.lighthouse.finalized_slot // 0' "${l1_manifest}" 2>/dev/null || echo "0")
    fi
    
    # Create summary JSON
    local summary_json
    summary_json=$(cat <<EOF
{
    "snapshot_created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "enclave_name": "${ENCLAVE_NAME}",
    "output_directory": "${output_dir}",
    "l1_state": {
        "finalized_block": ${geth_block},
        "finalized_slot": ${lighthouse_slot}
    },
    "networks": {
        "count": ${networks_count}
    },
    "files": {
        "docker_compose": "${output_dir}/docker-compose.yml",
        "l1_manifest": "${l1_manifest}",
        "log_file": "${output_dir}/snapshot.log"
    },
    "next_steps": [
        "Review the snapshot output in: ${output_dir}",
        "Start the environment: cd ${output_dir} && docker-compose up -d",
        "Check service logs: cd ${output_dir} && docker-compose logs -f",
        "Note: L2 services will perform initial sync from L1 on first run"
    ]
}
EOF
)
    
    # Write summary
    echo "${summary_json}" | jq '.' > "${summary_file}" || {
        log_error "Failed to create summary report"
        return 1
    }
    
    log_success "Summary report created: ${summary_file}"
    
    # Print summary to console
    log_info ""
    log_info "=========================================="
    log_info "Snapshot Creation Summary"
    log_info "=========================================="
    log_info "Enclave: ${ENCLAVE_NAME}"
    log_info "Output: ${output_dir}"
    log_info "L1 State: Block ${geth_block}, Slot ${lighthouse_slot}"
    log_info "Networks: ${networks_count}"
    log_info ""
    log_info "Next Steps:"
    log_info "  1. Review the snapshot output in: ${output_dir}"
    log_info "  2. Start the environment: cd ${output_dir} && docker-compose up -d"
    log_info "  3. Check service logs: cd ${output_dir} && docker-compose logs -f"
    log_info "  4. Note: L2 services will perform initial sync from L1 on first run"
    log_info ""
    
    return 0
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [ ${exit_code} -ne 0 ]; then
        log_error "Script failed with exit code ${exit_code}"
        if [ -n "${LOG_FILE}" ]; then
            log_error "Check log file for details: ${LOG_FILE}"
        fi
    fi
    
    # Cleanup enclave if requested
    if [ "${CLEANUP_ENCLAVE}" = "true" ] && [ -n "${ENCLAVE_NAME}" ]; then
        log_info "Cleaning up enclave: ${ENCLAVE_NAME}"
        kurtosis enclave rm --force "${ENCLAVE_NAME}" || true
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main function
main() {
    log_step "0" "Snapshot Creation"
    
    # Parse arguments
    parse_args "$@"
    
    # Setup logging
    setup_logging "${OUTPUT_DIR}" || {
        echo "Error: Failed to setup logging" >&2
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    
    # Check prerequisites
    log_section "Checking Prerequisites"
    if ! check_required_tools; then
        log_error "Prerequisites check failed"
        exit ${EXIT_CODE_PREREQ_ERROR}
    fi
    
    if ! check_output_dir "${OUTPUT_DIR}"; then
        log_error "Output directory check failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    log_success "Prerequisites check passed"
    
    # Generate or use provided args file
    if [ -z "${KURTOSIS_ARGS_FILE}" ]; then
        if [ -z "${NETWORKS_JSON}" ]; then
            log_error "Either --networks or --args-file must be provided"
            exit ${EXIT_CODE_VALIDATION_ERROR}
        fi
        
        KURTOSIS_ARGS_FILE="${OUTPUT_DIR}/kurtosis-args.json"
        if ! generate_args_file "${KURTOSIS_ARGS_FILE}" "${NETWORKS_JSON}"; then
            log_error "Failed to generate args file"
            exit ${EXIT_CODE_GENERAL_ERROR}
        fi
    else
        if [ ! -f "${KURTOSIS_ARGS_FILE}" ]; then
            log_error "Args file not found: ${KURTOSIS_ARGS_FILE}"
            exit ${EXIT_CODE_VALIDATION_ERROR}
        fi
        log_info "Using provided args file: ${KURTOSIS_ARGS_FILE}"
    fi
    
    # Run Kurtosis (unless skipped)
    if [ "${SKIP_KURTOSIS}" != "true" ]; then
        if ! run_kurtosis "${ENCLAVE_NAME}" "${KURTOSIS_ARGS_FILE}"; then
            log_error "Kurtosis run failed"
            exit ${EXIT_CODE_KURTOSIS_ERROR}
        fi
    else
        log_info "Skipping kurtosis run (--skip-kurtosis flag set)"
    fi
    
    # Run post-processing
    if ! run_post_processing "${ENCLAVE_NAME}" "${OUTPUT_DIR}" "${NETWORKS_JSON}"; then
        log_error "Post-processing failed"
        exit ${EXIT_CODE_GENERAL_ERROR}
    fi
    
    # Validate output
    if ! validate_output "${OUTPUT_DIR}"; then
        log_error "Output validation failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    # Create summary
    if ! create_summary "${OUTPUT_DIR}"; then
        log_warn "Failed to create summary report (continuing)"
    fi
    
    # Run verification if not skipped
    if [ "${SKIP_VERIFICATION}" != "true" ]; then
        log_section "Running Snapshot Verification"
        
        local verify_args=("--output-dir" "${OUTPUT_DIR}")
        
        if [ -n "${NETWORKS_JSON}" ] && [ -f "${NETWORKS_JSON}" ]; then
            verify_args+=("--networks-json" "${NETWORKS_JSON}")
        fi
        
        if [ "${VERIFY_RUNTIME}" = "true" ]; then
            verify_args+=("--start-env")
        fi
        
        if "${SCRIPT_DIR}/verify-snapshot.sh" "${verify_args[@]}"; then
            log_success "Snapshot verification passed"
        else
            local verify_exit_code=$?
            log_warn "Snapshot verification failed (exit code: ${verify_exit_code})"
            log_warn "Snapshot was created successfully, but verification had issues"
            log_warn "You can run verification manually: ${SCRIPT_DIR}/verify-snapshot.sh --output-dir ${OUTPUT_DIR}"
        fi
    else
        log_info "Verification skipped (--skip-verification flag set)"
    fi
    
    log_success "Snapshot creation completed successfully!"
    log_info "Output directory: ${OUTPUT_DIR}"
    log_info "Log file: ${LOG_FILE}"
}

# Run main function
main "$@"
