#!/bin/bash
# End-to-end test script for snapshot feature
#
# This script runs the complete snapshot creation and verification flow:
# 1. Creates a snapshot using snapshot.sh
# 2. Runs static validation
# 3. Optionally runs runtime verification (starts docker-compose)
# 4. Provides clear pass/fail results
#
# This script can be used for:
# - Manual testing during development
# - CI/CD integration
# - Validation after changes

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"

# Default values
ENCLAVE_NAME=""
OUTPUT_DIR=""
NETWORKS_JSON=""
L1_WAIT_BLOCKS=10
CLEANUP_ENCLAVE=false
SKIP_KURTOSIS=false
SKIP_VERIFICATION=false
VERIFY_RUNTIME=false
CLEANUP_OUTPUT=false

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2
EXIT_CODE_PREREQ_ERROR=3
EXIT_CODE_KURTOSIS_ERROR=4
EXIT_CODE_VERIFICATION_ERROR=5

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

End-to-end test script for snapshot feature.

This script:
1. Creates a snapshot using snapshot.sh
2. Runs static validation
3. Optionally runs runtime verification (starts docker-compose)
4. Provides clear pass/fail results

Options:
    --enclave-name NAME       Kurtosis enclave name (required)
    --output-dir DIR          Output directory for snapshot (required)
    --networks FILE           JSON file with network configs (required)
    --l1-wait-blocks N        Number of blocks to wait for L1 finalization (default: 10)
    --cleanup-enclave         Clean up enclave after snapshot (default: false)
    --cleanup-output          Clean up output directory before starting (default: false)
    --skip-kurtosis           Skip kurtosis run (for testing post-processing only)
    --skip-verification      Skip snapshot verification (default: false)
    --verify-runtime          Run runtime verification (starts docker-compose) (default: false)
    -h, --help                Show this help message

Example:
    $0 \\
        --enclave-name test \\
        --output-dir ./test-output \\
        --networks ./test-networks.json \\
        --verify-runtime

    # Test with cleanup
    $0 \\
        --enclave-name test \\
        --output-dir ./test-output \\
        --networks ./test-networks.json \\
        --cleanup-enclave \\
        --cleanup-output \\
        --verify-runtime
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
            --cleanup-enclave)
                CLEANUP_ENCLAVE=true
                shift
                ;;
            --cleanup-output)
                CLEANUP_OUTPUT=true
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
    
    if [ -z "${NETWORKS_JSON}" ]; then
        echo "Error: --networks is required" >&2
        usage
    fi
}

# Cleanup output directory
cleanup_output() {
    if [ "${CLEANUP_OUTPUT}" = "true" ] && [ -d "${OUTPUT_DIR}" ]; then
        log_section "Cleaning Up Output Directory"
        log_info "Removing: ${OUTPUT_DIR}"
        rm -rf "${OUTPUT_DIR}"
        log_success "Output directory cleaned"
    fi
}

# Run snapshot creation
run_snapshot_creation() {
    log_section "Step 1: Creating Snapshot"
    
    local snapshot_args=(
        "--enclave-name" "${ENCLAVE_NAME}"
        "--output-dir" "${OUTPUT_DIR}"
        "--networks" "${NETWORKS_JSON}"
        "--l1-wait-blocks" "${L1_WAIT_BLOCKS}"
    )
    
    if [ "${CLEANUP_ENCLAVE}" = "true" ]; then
        snapshot_args+=("--cleanup-enclave")
    fi
    
    if [ "${SKIP_KURTOSIS}" = "true" ]; then
        snapshot_args+=("--skip-kurtosis")
    fi
    
    if [ "${SKIP_VERIFICATION}" = "true" ]; then
        snapshot_args+=("--skip-verification")
    fi
    
    if [ "${VERIFY_RUNTIME}" = "true" ]; then
        snapshot_args+=("--verify-runtime")
    fi
    
    log_info "Running snapshot creation..."
    log_info "Command: ${SCRIPT_DIR}/snapshot.sh ${snapshot_args[*]}"
    
    if "${SCRIPT_DIR}/snapshot.sh" "${snapshot_args[@]}"; then
        log_success "Snapshot creation completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Snapshot creation failed with exit code ${exit_code}"
        return ${exit_code}
    fi
}

# Run verification separately (if not already run)
run_verification() {
    if [ "${SKIP_VERIFICATION}" = "true" ]; then
        log_info "Verification skipped (--skip-verification flag set)"
        return 0
    fi
    
    log_section "Step 2: Running Verification"
    
    local verify_args=("--output-dir" "${OUTPUT_DIR}")
    
    if [ -n "${NETWORKS_JSON}" ] && [ -f "${NETWORKS_JSON}" ]; then
        verify_args+=("--networks-json" "${NETWORKS_JSON}")
    fi
    
    if [ "${VERIFY_RUNTIME}" = "true" ]; then
        verify_args+=("--start-env")
    fi
    
    log_info "Running verification..."
    log_info "Command: ${SCRIPT_DIR}/verify-snapshot.sh ${verify_args[*]}"
    
    if "${SCRIPT_DIR}/verify-snapshot.sh" "${verify_args[@]}"; then
        log_success "Verification completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Verification failed with exit code ${exit_code}"
        return ${exit_code}
    fi
}

# Print test summary
print_test_summary() {
    local snapshot_created=$1
    local verification_passed=$2
    
    log_section "Test Summary"
    log_info ""
    log_info "=========================================="
    log_info "Snapshot Test Results"
    log_info "=========================================="
    log_info ""
    log_info "Enclave: ${ENCLAVE_NAME}"
    log_info "Output: ${OUTPUT_DIR}"
    log_info "Networks: ${NETWORKS_JSON}"
    log_info ""
    
    if [ "${snapshot_created}" = "true" ]; then
        log_success "✓ Snapshot creation: PASSED"
    else
        log_error "✗ Snapshot creation: FAILED"
    fi
    
    if [ "${SKIP_VERIFICATION}" = "true" ]; then
        log_info "○ Verification: SKIPPED"
    elif [ "${verification_passed}" = "true" ]; then
        log_success "✓ Verification: PASSED"
    else
        log_error "✗ Verification: FAILED"
    fi
    
    log_info ""
    
    if [ "${snapshot_created}" = "true" ] && [ "${verification_passed}" = "true" ]; then
        log_success "=========================================="
        log_success "ALL TESTS PASSED"
        log_success "=========================================="
        log_info ""
        log_info "Snapshot is ready to use:"
        log_info "  cd ${OUTPUT_DIR}"
        log_info "  docker-compose up -d"
        return 0
    else
        log_error "=========================================="
        log_error "SOME TESTS FAILED"
        log_error "=========================================="
        log_info ""
        log_info "Check log file for details:"
        log_info "  ${OUTPUT_DIR}/snapshot.log"
        return 1
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?
    
    if [ ${exit_code} -ne 0 ]; then
        log_error "Test failed with exit code ${exit_code}"
        if [ -n "${LOG_FILE}" ]; then
            log_error "Check log file for details: ${LOG_FILE}"
        fi
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main function
main() {
    log_step "0" "Snapshot End-to-End Test"
    
    # Parse arguments
    parse_args "$@"
    
    # Setup logging
    setup_logging "${OUTPUT_DIR}" || {
        echo "Error: Failed to setup logging" >&2
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    
    # Cleanup output if requested
    cleanup_output
    
    log_info "Starting snapshot end-to-end test"
    log_info "Enclave: ${ENCLAVE_NAME}"
    log_info "Output: ${OUTPUT_DIR}"
    log_info "Networks: ${NETWORKS_JSON}"
    log_info ""
    
    # Track test results
    local snapshot_created=false
    local verification_passed=false
    
    # Step 1: Create snapshot
    if run_snapshot_creation; then
        snapshot_created=true
    else
        print_test_summary false false
        exit ${EXIT_CODE_KURTOSIS_ERROR}
    fi
    
    # Step 2: Run verification (if not already run by snapshot.sh)
    # Note: snapshot.sh already runs verification, but we can run it again
    # for explicit testing or if it was skipped
    if [ "${SKIP_VERIFICATION}" != "true" ]; then
        if run_verification; then
            verification_passed=true
        else
            verification_passed=false
            # Don't exit here - we want to show the summary
        fi
    else
        verification_passed=true  # Consider it passed if skipped
    fi
    
    # Print summary and exit
    if print_test_summary "${snapshot_created}" "${verification_passed}"; then
        exit 0
    else
        exit ${EXIT_CODE_VERIFICATION_ERROR}
    fi
}

# Run main function
main "$@"
