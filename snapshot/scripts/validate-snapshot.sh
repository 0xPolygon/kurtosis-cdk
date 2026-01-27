#!/bin/bash
# Comprehensive validation script for snapshot
#
# This script validates all components of a snapshot:
# - Prerequisites
# - Network configurations
# - Extracted L1 state
# - Config files
# - Docker images
# - Docker compose file
# - Required files

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"
source "${UTILS_DIR}/prerequisites.sh"
source "${UTILS_DIR}/validation.sh"

# Default values
OUTPUT_DIR=""
NETWORKS_JSON=""
VALIDATE_PREREQS=true
VALIDATE_NETWORKS=true
VALIDATE_STATE=true
VALIDATE_CONFIGS=true
VALIDATE_IMAGES=true
VALIDATE_COMPOSE=true
VALIDATE_FILES=true

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2
EXIT_CODE_PREREQ_ERROR=3

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Comprehensive validation script for snapshot.

Options:
    --output-dir DIR          Output directory from snapshot creation (required)
    --networks-json FILE      Path to networks configuration JSON (optional, for network validation)
    --skip-prereqs            Skip prerequisite checks
    --skip-networks           Skip network config validation
    --skip-state              Skip L1 state validation
    --skip-configs            Skip config file validation
    --skip-images             Skip Docker image validation
    --skip-compose            Skip docker-compose validation
    --skip-files              Skip required files validation
    -h, --help                Show this help message

Example:
    $0 \\
        --output-dir ./snapshot-output \\
        --networks-json ./networks.json
EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --networks-json)
                NETWORKS_JSON="$2"
                shift 2
                ;;
            --skip-prereqs)
                VALIDATE_PREREQS=false
                shift
                ;;
            --skip-networks)
                VALIDATE_NETWORKS=false
                shift
                ;;
            --skip-state)
                VALIDATE_STATE=false
                shift
                ;;
            --skip-configs)
                VALIDATE_CONFIGS=false
                shift
                ;;
            --skip-images)
                VALIDATE_IMAGES=false
                shift
                ;;
            --skip-compose)
                VALIDATE_COMPOSE=false
                shift
                ;;
            --skip-files)
                VALIDATE_FILES=false
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
    if [ -z "${OUTPUT_DIR}" ]; then
        echo "Error: --output-dir is required" >&2
        usage
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_section "Validating Prerequisites"
    
    local errors=0
    
    if ! check_required_tools; then
        errors=$((errors + 1))
    fi
    
    if [ ${errors} -eq 0 ]; then
        log_success "Prerequisites validation passed"
        return 0
    else
        log_error "Prerequisites validation failed: ${errors} error(s)"
        return 1
    fi
}

# Validate network configurations
validate_network_configs() {
    log_section "Validating Network Configurations"
    
    if [ -z "${NETWORKS_JSON}" ]; then
        log_warn "Networks JSON not provided, skipping network validation"
        return 0
    fi
    
    if [ ! -f "${NETWORKS_JSON}" ]; then
        log_error "Networks JSON file not found: ${NETWORKS_JSON}"
        return 1
    fi
    
    if validate_networks_config "${NETWORKS_JSON}"; then
        log_success "Network configurations validation passed"
        return 0
    else
        log_error "Network configurations validation failed"
        return 1
    fi
}

# Validate L1 state
validate_l1_state_check() {
    log_section "Validating L1 State"
    
    local l1_state_dir="${OUTPUT_DIR}/l1-state"
    
    if [ ! -d "${l1_state_dir}" ]; then
        log_error "L1 state directory not found: ${l1_state_dir}"
        return 1
    fi
    
    if validate_l1_state "${l1_state_dir}"; then
        log_success "L1 state validation passed"
        return 0
    else
        log_error "L1 state validation failed"
        return 1
    fi
}

# Validate config files
validate_config_files() {
    log_section "Validating Config Files"
    
    local errors=0
    local configs_dir="${OUTPUT_DIR}/configs"
    
    if [ ! -d "${configs_dir}" ]; then
        log_error "Configs directory not found: ${configs_dir}"
        return 1
    fi
    
    # Validate agglayer config
    local agglayer_config="${configs_dir}/agglayer/config.toml"
    if [ -f "${agglayer_config}" ]; then
        if validate_config_file "${agglayer_config}" "toml"; then
            log_info "Agglayer config validated"
        else
            log_error "Agglayer config validation failed"
            errors=$((errors + 1))
        fi
    else
        log_warn "Agglayer config not found: ${agglayer_config}"
    fi
    
    # Validate network configs
    for network_dir in "${configs_dir}"/*/; do
        if [ -d "${network_dir}" ]; then
            local network_id=$(basename "${network_dir}")
            log_debug "Validating configs for network ${network_id}"

            # Note: CDK-Node is not used in snapshot mode; only AggKit is used

            # Validate AggKit config
            local aggkit_config="${network_dir}/aggkit-config.toml"
            if [ -f "${aggkit_config}" ]; then
                if validate_config_file "${aggkit_config}" "toml"; then
                    log_debug "AggKit config validated for network ${network_id}"
                else
                    log_error "AggKit config validation failed for network ${network_id}"
                    errors=$((errors + 1))
                fi
            fi
            
            # Validate genesis JSON
            local genesis_json="${network_dir}/genesis.json"
            if [ -f "${genesis_json}" ]; then
                if validate_config_file "${genesis_json}" "json"; then
                    log_debug "Genesis JSON validated for network ${network_id}"
                else
                    log_error "Genesis JSON validation failed for network ${network_id}"
                    errors=$((errors + 1))
                fi
            fi
        fi
    done
    
    if [ ${errors} -eq 0 ]; then
        log_success "Config files validation passed"
        return 0
    else
        log_error "Config files validation failed: ${errors} error(s)"
        return 1
    fi
}

# Validate Docker images
validate_docker_images() {
    log_section "Validating Docker Images"
    
    local errors=0
    local images_manifest="${OUTPUT_DIR}/l1-images/manifest.json"
    
    if [ ! -f "${images_manifest}" ]; then
        log_warn "L1 images manifest not found: ${images_manifest}"
        log_warn "Skipping Docker image validation"
        return 0
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warn "jq not available, skipping image tag extraction"
        return 0
    fi
    
    # Get image tags from manifest
    local geth_image=$(jq -r '.geth.image_tag // ""' "${images_manifest}" 2>/dev/null || echo "")
    local lighthouse_image=$(jq -r '.lighthouse.image_tag // ""' "${images_manifest}" 2>/dev/null || echo "")
    
    # Validate geth image
    if [ -n "${geth_image}" ]; then
        if validate_docker_image "${geth_image}"; then
            log_info "Geth image validated: ${geth_image}"
        else
            log_error "Geth image validation failed: ${geth_image}"
            errors=$((errors + 1))
        fi
    else
        log_warn "Geth image tag not found in manifest"
    fi
    
    # Validate lighthouse image
    if [ -n "${lighthouse_image}" ]; then
        if validate_docker_image "${lighthouse_image}"; then
            log_info "Lighthouse image validated: ${lighthouse_image}"
        else
            log_error "Lighthouse image validation failed: ${lighthouse_image}"
            errors=$((errors + 1))
        fi
    else
        log_warn "Lighthouse image tag not found in manifest"
    fi
    
    if [ ${errors} -eq 0 ]; then
        log_success "Docker images validation passed"
        return 0
    else
        log_error "Docker images validation failed: ${errors} error(s)"
        return 1
    fi
}

# Validate docker-compose file
validate_docker_compose_file() {
    log_section "Validating Docker Compose File"
    
    local compose_file="${OUTPUT_DIR}/docker-compose.yml"
    
    if [ ! -f "${compose_file}" ]; then
        log_error "Docker compose file not found: ${compose_file}"
        return 1
    fi
    
    if validate_docker_compose "${compose_file}"; then
        log_success "Docker compose validation passed"
        return 0
    else
        log_error "Docker compose validation failed"
        return 1
    fi
}

# Validate required files
validate_required_files_check() {
    log_section "Validating Required Files"
    
    local required_files=(
        "l1-state/manifest.json"
        "config-processing-manifest.json"
        "port-mapping.json"
        "keystore-mapping.json"
    )
    
    if validate_required_files "${OUTPUT_DIR}" "${required_files[@]}"; then
        log_success "Required files validation passed"
        return 0
    else
        log_error "Required files validation failed"
        return 1
    fi
}

# Main validation function
main() {
    log_step "1" "Snapshot Validation"
    
    # Parse arguments
    parse_args "$@"
    
    # Setup logging
    setup_logging "${OUTPUT_DIR}" || {
        echo "Error: Failed to setup logging" >&2
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    
    # Check output directory
    if ! check_output_dir "${OUTPUT_DIR}"; then
        log_error "Output directory check failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    log_info "Validating snapshot in: ${OUTPUT_DIR}"
    log_info ""
    
    # Track validation results
    local total_errors=0
    local validation_passed=true
    
    # Run validations
    if [ "${VALIDATE_PREREQS}" = "true" ]; then
        if ! validate_prerequisites; then
            total_errors=$((total_errors + 1))
            validation_passed=false
        fi
    fi
    
    if [ "${VALIDATE_NETWORKS}" = "true" ]; then
        if ! validate_network_configs; then
            total_errors=$((total_errors + 1))
            validation_passed=false
        fi
    fi
    
    if [ "${VALIDATE_STATE}" = "true" ]; then
        if ! validate_l1_state_check; then
            total_errors=$((total_errors + 1))
            validation_passed=false
        fi
    fi
    
    if [ "${VALIDATE_CONFIGS}" = "true" ]; then
        if ! validate_config_files; then
            total_errors=$((total_errors + 1))
            validation_passed=false
        fi
    fi
    
    if [ "${VALIDATE_IMAGES}" = "true" ]; then
        if ! validate_docker_images; then
            total_errors=$((total_errors + 1))
            validation_passed=false
        fi
    fi
    
    if [ "${VALIDATE_COMPOSE}" = "true" ]; then
        if ! validate_docker_compose_file; then
            total_errors=$((total_errors + 1))
            validation_passed=false
        fi
    fi
    
    if [ "${VALIDATE_FILES}" = "true" ]; then
        if ! validate_required_files_check; then
            total_errors=$((total_errors + 1))
            validation_passed=false
        fi
    fi
    
    # Print summary
    log_section "Validation Summary"
    if [ "${validation_passed}" = "true" ]; then
        log_success "All validations passed!"
        log_info "Snapshot is valid and ready to use"
        return 0
    else
        log_error "Validation failed: ${total_errors} validation category(ies) failed"
        log_error "Check log file for details: ${LOG_FILE}"
        return ${EXIT_CODE_VALIDATION_ERROR}
    fi
}

# Run main function
main "$@"
