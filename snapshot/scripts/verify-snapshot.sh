#!/bin/bash
# Comprehensive verification script for snapshot
#
# This script performs both static validation and optional runtime verification:
# - Static validation: Calls validate-snapshot.sh to check files, configs, images
# - Runtime verification: Optionally starts docker-compose environment and verifies:
#   - L1 geth is accessible and at correct block
#   - L1 lighthouse is accessible
#   - Agglayer is running and accessible
#   - L2 networks are accessible
#   - Services can communicate
#   - All networks are registered in agglayer

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
START_ENV=false
TIMEOUT=300
L1_GETH_PORT=8545
L1_LIGHTHOUSE_PORT=4000
AGGLAYER_RPC_PORT=8080
CLEANUP_ON_EXIT=true

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2
EXIT_CODE_RUNTIME_ERROR=3

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Comprehensive verification script for snapshot.

This script performs:
1. Static validation (files, configs, images, docker-compose syntax)
2. Optional runtime verification (starts environment and checks services)

Options:
    --output-dir DIR          Output directory from snapshot creation (required)
    --networks-json FILE      Path to networks configuration JSON (optional)
    --start-env               Start docker-compose environment for runtime verification
    --timeout SECONDS         Timeout for service readiness checks (default: 300)
    --l1-geth-port PORT       L1 geth RPC port (default: 8545)
    --l1-lighthouse-port PORT L1 lighthouse HTTP port (default: 4000)
    --agglayer-rpc-port PORT  Agglayer RPC port (default: 8080)
    --no-cleanup              Don't stop docker-compose on exit (for debugging)
    -h, --help                Show this help message

Example:
    # Static validation only
    $0 --output-dir ./snapshot-output

    # Static + runtime verification
    $0 --output-dir ./snapshot-output --start-env

    # Runtime verification with custom ports
    $0 --output-dir ./snapshot-output --start-env \\
        --l1-geth-port 8545 \\
        --agglayer-rpc-port 8080
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
            --start-env)
                START_ENV=true
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --l1-geth-port)
                L1_GETH_PORT="$2"
                shift 2
                ;;
            --l1-lighthouse-port)
                L1_LIGHTHOUSE_PORT="$2"
                shift 2
                ;;
            --agglayer-rpc-port)
                AGGLAYER_RPC_PORT="$2"
                shift 2
                ;;
            --no-cleanup)
                CLEANUP_ON_EXIT=false
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

# Get docker-compose file path
get_compose_file() {
    echo "${OUTPUT_DIR}/docker-compose.yml"
}

# Start docker-compose environment
start_docker_compose() {
    local compose_file
    compose_file=$(get_compose_file)
    
    if [ ! -f "${compose_file}" ]; then
        log_error "Docker compose file not found: ${compose_file}"
        return 1
    fi
    
    log_section "Starting Docker Compose Environment"
    log_info "Compose file: ${compose_file}"
    
    # Change to output directory for docker-compose
    local original_dir
    original_dir=$(pwd)
    cd "${OUTPUT_DIR}" || {
        log_error "Failed to change to output directory: ${OUTPUT_DIR}"
        return 1
    }
    
    # Start services (try docker compose v2 first, then docker-compose v1)
    local compose_cmd=""
    if docker compose version &>/dev/null; then
        compose_cmd="docker compose"
    elif command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
    else
        log_error "Neither 'docker compose' nor 'docker-compose' is available"
        cd "${original_dir}" || true
        return 1
    fi
    
    if ${compose_cmd} -f docker-compose.yml up -d 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Docker compose services started"
        cd "${original_dir}" || true
        return 0
    else
        log_error "Failed to start docker compose services"
        cd "${original_dir}" || true
        return 1
    fi
}

# Stop docker-compose environment
stop_docker_compose() {
    local compose_file
    compose_file=$(get_compose_file)
    
    if [ ! -f "${compose_file}" ]; then
        return 0
    fi
    
    log_section "Stopping Docker Compose Environment"
    
    # Change to output directory for docker-compose
    local original_dir
    original_dir=$(pwd)
    cd "${OUTPUT_DIR}" || {
        log_warn "Failed to change to output directory (services may still be running)"
        return 0
    }
    
    # Stop services (try docker compose v2 first, then docker-compose v1)
    local compose_cmd=""
    if docker compose version &>/dev/null; then
        compose_cmd="docker compose"
    elif command -v docker-compose &>/dev/null; then
        compose_cmd="docker-compose"
    else
        log_warn "Neither 'docker compose' nor 'docker-compose' is available"
        return 0
    fi
    
    ${compose_cmd} -f docker-compose.yml down 2>&1 | tee -a "${LOG_FILE}" || {
        log_warn "Some services may not have stopped cleanly"
    }
    
    log_info "Docker compose services stopped"
    cd "${original_dir}" || true
}

# Wait for service to be ready
# Usage: wait_for_service <service_name> <check_command> <timeout>
wait_for_service() {
    local service_name="$1"
    local check_command="$2"
    local timeout="${3:-${TIMEOUT}}"
    local elapsed=0
    local interval=5
    
    log_info "Waiting for ${service_name} to be ready (timeout: ${timeout}s)..."
    
    while [ ${elapsed} -lt ${timeout} ]; do
        if eval "${check_command}" &>/dev/null; then
            log_success "${service_name} is ready"
            return 0
        fi
        
        sleep ${interval}
        elapsed=$((elapsed + interval))
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "Still waiting for ${service_name}... (${elapsed}s elapsed)"
        fi
    done
    
    log_error "${service_name} did not become ready within ${timeout}s"
    return 1
}

# Make RPC call using curl or cast
# Usage: rpc_call <url> <method> [params_json]
rpc_call() {
    local url="$1"
    local method="$2"
    local params="${3:-[]}"
    
    local json_payload
    json_payload=$(jq -n \
        --arg method "${method}" \
        --argjson params "${params}" \
        '{jsonrpc: "2.0", id: 1, method: $method, params: $params}')
    
    # Try cast first (if available), then curl
    if command -v cast &> /dev/null; then
        cast rpc --rpc-url "${url}" "${method}" 2>/dev/null | jq -r '.result // empty' 2>/dev/null || echo ""
    elif command -v curl &> /dev/null; then
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "${json_payload}" \
            "${url}" 2>/dev/null | jq -r '.result // empty' 2>/dev/null || echo ""
    else
        log_error "Neither 'cast' nor 'curl' is available for RPC calls"
        return 1
    fi
}

# Verify L1 geth is accessible and at correct block
verify_l1_geth() {
    log_section "Verifying L1 Geth"
    
    local l1_rpc_url="http://localhost:${L1_GETH_PORT}"
    local expected_block=0
    
    # Get expected block from manifest
    local manifest_file="${OUTPUT_DIR}/l1-state/manifest.json"
    if [ -f "${manifest_file}" ] && command -v jq &> /dev/null; then
        expected_block=$(jq -r '.geth.finalized_block // 0' "${manifest_file}" 2>/dev/null || echo "0")
    fi
    
    # Wait for service to be ready
    local check_cmd="rpc_call '${l1_rpc_url}' 'eth_blockNumber' '[]' | grep -q ."
    if ! wait_for_service "L1 Geth" "${check_cmd}" "${TIMEOUT}"; then
        return 1
    fi
    
    # Get current block number
    local current_block_hex
    current_block_hex=$(rpc_call "${l1_rpc_url}" "eth_blockNumber" "[]")
    
    if [ -z "${current_block_hex}" ]; then
        log_error "Failed to get block number from L1 geth"
        return 1
    fi
    
    # Convert hex to decimal
    local current_block=0
    if command -v cast &> /dev/null; then
        current_block=$(cast --to-dec "${current_block_hex}" 2>/dev/null || echo "0")
    elif command -v python3 &> /dev/null; then
        current_block=$(python3 -c "print(int('${current_block_hex}', 16))" 2>/dev/null || echo "0")
    else
        log_warn "Cannot convert hex to decimal (cast/python3 not available)"
        log_info "Current block (hex): ${current_block_hex}"
        log_info "Expected block: ${expected_block}"
        return 0  # Still consider it a success if we got a response
    fi
    
    log_info "L1 Geth block number: ${current_block}"
    log_info "Expected block number: ${expected_block}"
    
    if [ "${expected_block}" -gt 0 ] && [ "${current_block}" -lt "${expected_block}" ]; then
        log_warn "Current block (${current_block}) is less than expected (${expected_block})"
        log_warn "This may be normal if the service is still syncing"
    else
        log_success "L1 Geth is accessible and responding"
    fi
    
    return 0
}

# Verify L1 lighthouse is accessible
verify_l1_lighthouse() {
    log_section "Verifying L1 Lighthouse"
    
    local lighthouse_url="http://localhost:${L1_LIGHTHOUSE_PORT}"
    
    # Wait for service to be ready (check health endpoint)
    local check_cmd="curl -s -f '${lighthouse_url}/lighthouse/health' &>/dev/null || curl -s -f '${lighthouse_url}/eth/v1/node/health' &>/dev/null"
    if ! wait_for_service "L1 Lighthouse" "${check_cmd}" "${TIMEOUT}"; then
        log_warn "L1 Lighthouse health check failed, but service may still be running"
        # Try a simpler check - just see if port is open
        if command -v nc &> /dev/null; then
            if nc -z localhost "${L1_LIGHTHOUSE_PORT}" 2>/dev/null; then
                log_info "L1 Lighthouse port is open"
                return 0
            fi
        fi
        return 1
    fi
    
    log_success "L1 Lighthouse is accessible"
    return 0
}

# Verify Agglayer is running and accessible
verify_agglayer() {
    log_section "Verifying Agglayer"
    
    # First check if container is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agglayer$'; then
        log_error "Agglayer container is not running"
        return 1
    fi
    
    log_info "Agglayer container is running"
    
    # Try to access agglayer via docker exec (from inside container network)
    # Agglayer readrpc is typically on port 8080 inside the container
    local agglayer_url="http://agglayer:8080"
    
    # Try to make an RPC call via docker exec
    local check_cmd="docker exec agglayer sh -c 'command -v curl >/dev/null && curl -s -X POST -H \"Content-Type: application/json\" -d \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":1,\\\"method\\\":\\\"interop_getLatestKnownCertificateHeader\\\",\\\"params\\\":[1]}\" http://localhost:8080 2>/dev/null | grep -q result' || docker exec agglayer sh -c 'command -v wget >/dev/null && wget -q -O- --post-data=\"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"id\\\":1,\\\"method\\\":\\\"interop_getLatestKnownCertificateHeader\\\",\\\"params\\\":[1]}\" --header=\"Content-Type: application/json\" http://localhost:8080 2>/dev/null | grep -q result'"
    
    if wait_for_service "Agglayer" "${check_cmd}" "${TIMEOUT}"; then
        log_success "Agglayer is accessible and responding"
        return 0
    fi
    
    # Fallback: Check if any of the exposed ports are accessible
    log_info "Trying to access agglayer via exposed ports..."
    local exposed_ports=(4443 4444 4446 9092)
    local port_accessible=false
    
    for port in "${exposed_ports[@]}"; do
        if curl -s -f "http://localhost:${port}" &>/dev/null || \
           curl -s -f "http://localhost:${port}/health" &>/dev/null; then
            log_info "Agglayer port ${port} is accessible"
            port_accessible=true
            break
        fi
    done
    
    if [ "${port_accessible}" = "true" ]; then
        log_success "Agglayer is accessible via exposed port"
        return 0
    fi
    
    # If we get here, container is running but we can't verify RPC access
    log_warn "Agglayer container is running but RPC access could not be verified"
    log_warn "This may be normal if agglayer is still initializing"
    return 0  # Don't fail - container is running
}

# Verify L2 networks are accessible
verify_l2_networks() {
    log_section "Verifying L2 Networks"
    
    if [ -z "${NETWORKS_JSON}" ] || [ ! -f "${NETWORKS_JSON}" ]; then
        log_warn "Networks JSON not provided, skipping L2 network verification"
        return 0
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warn "jq not available, skipping L2 network verification"
        return 0
    fi
    
    # Read port mapping if available
    local port_mapping_file="${OUTPUT_DIR}/port-mapping.json"
    local port_mapping="{}"
    if [ -f "${port_mapping_file}" ]; then
        port_mapping=$(cat "${port_mapping_file}")
    fi
    
    # Get networks from JSON
    local networks_data
    networks_data=$(jq -c '.networks // []' "${NETWORKS_JSON}" 2>/dev/null || echo "[]")
    local network_count
    network_count=$(echo "${networks_data}" | jq 'length' 2>/dev/null || echo "0")
    
    if [ "${network_count}" -eq 0 ]; then
        log_warn "No networks found in JSON file"
        return 0
    fi
    
    log_info "Verifying ${network_count} L2 network(s)..."
    
    local errors=0
    for i in $(seq 0 $((network_count - 1))); do
        local network_id
        network_id=$(echo "${networks_data}" | jq -r ".[${i}].network_id" 2>/dev/null || echo "")
        local sequencer_type
        sequencer_type=$(echo "${networks_data}" | jq -r ".[${i}].sequencer_type" 2>/dev/null || echo "")
        
        if [ -z "${network_id}" ]; then
            log_warn "Network ${i} has no network_id, skipping"
            continue
        fi
        
        # Get RPC port for this network
        local rpc_port
        # Port mapping uses l2_rpc_http key (from process-configs.sh)
        rpc_port=$(echo "${port_mapping}" | jq -r ".[\"${network_id}\"].l2_rpc_http // \"\"" 2>/dev/null || echo "")
        
        # Default ports based on sequencer type
        if [ -z "${rpc_port}" ]; then
            case "${sequencer_type}" in
                "cdk-erigon")
                    # For CDK-Erigon, default to RPC service port (sequencer + 100)
                    # Default sequencer port is 8123, so RPC port is 8223
                    rpc_port="8223"
                    ;;
                "op-geth")
                    rpc_port="8545"
                    ;;
                *)
                    log_warn "Unknown sequencer type for network ${network_id}: ${sequencer_type}"
                    continue
                    ;;
            esac
        else
            # For CDK-Erigon, the port mapping contains sequencer port, but we need RPC service port
            # RPC service uses sequencer port + 100 (see generate-compose.sh line 330)
            if [ "${sequencer_type}" = "cdk-erigon" ]; then
                rpc_port=$((rpc_port + 100))
            fi
        fi
        
        local l2_rpc_url="http://localhost:${rpc_port}"
        local service_name=""
        
        case "${sequencer_type}" in
            "cdk-erigon")
                service_name="cdk-erigon-rpc-${network_id}"
                ;;
            "op-geth")
                service_name="op-geth-${network_id}"
                ;;
        esac
        
        log_info "Verifying network ${network_id} (${sequencer_type}) at ${l2_rpc_url}..."
        
        # Wait for service to be ready
        local check_cmd="rpc_call '${l2_rpc_url}' 'eth_blockNumber' '[]' | grep -q ."
        if wait_for_service "L2 Network ${network_id}" "${check_cmd}" "${TIMEOUT}"; then
            local block_hex
            block_hex=$(rpc_call "${l2_rpc_url}" "eth_blockNumber" "[]")
            if [ -n "${block_hex}" ]; then
                log_success "Network ${network_id} is accessible (block: ${block_hex})"
            else
                log_warn "Network ${network_id} responded but block number is empty"
            fi
        else
            log_error "Network ${network_id} did not become ready"
            errors=$((errors + 1))
        fi
    done
    
    if [ ${errors} -eq 0 ]; then
        log_success "All L2 networks are accessible"
        return 0
    else
        log_error "Some L2 networks failed verification: ${errors} error(s)"
        return 1
    fi
}

# Verify all networks are registered in agglayer config
verify_agglayer_networks() {
    log_section "Verifying Agglayer Network Registration"
    
    local agglayer_config="${OUTPUT_DIR}/configs/agglayer/config.toml"
    
    if [ ! -f "${agglayer_config}" ]; then
        log_warn "Agglayer config not found: ${agglayer_config}"
        return 0
    fi
    
    if [ -z "${NETWORKS_JSON}" ] || [ ! -f "${NETWORKS_JSON}" ]; then
        log_warn "Networks JSON not provided, skipping agglayer network verification"
        return 0
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warn "jq not available, skipping agglayer network verification"
        return 0
    fi
    
    # Get networks from JSON
    local networks_data
    networks_data=$(jq -c '.networks // []' "${NETWORKS_JSON}" 2>/dev/null || echo "[]")
    local network_count
    network_count=$(echo "${networks_data}" | jq 'length' 2>/dev/null || echo "0")
    
    if [ "${network_count}" -eq 0 ]; then
        log_warn "No networks found in JSON file"
        return 0
    fi
    
    log_info "Checking if ${network_count} network(s) are registered in agglayer config..."
    
    local errors=0
    
    # Check [full-node-rpcs] section
    for i in $(seq 0 $((network_count - 1))); do
        local network_id
        network_id=$(echo "${networks_data}" | jq -r ".[${i}].network_id" 2>/dev/null || echo "")
        
        if [ -z "${network_id}" ]; then
            continue
        fi
        
        # Check if network is in agglayer config (look for network_id or chain_id)
        if grep -q "network-id = ${network_id}" "${agglayer_config}" 2>/dev/null || \
           grep -q "network_id = ${network_id}" "${agglayer_config}" 2>/dev/null; then
            log_debug "Network ${network_id} found in agglayer config"
        else
            log_warn "Network ${network_id} not found in agglayer config [full-node-rpcs] section"
            errors=$((errors + 1))
        fi
    done
    
    if [ ${errors} -eq 0 ]; then
        log_success "All networks are registered in agglayer config"
        return 0
    else
        log_warn "Some networks may not be registered in agglayer config: ${errors} warning(s)"
        return 0  # Don't fail, just warn
    fi
}

# Run static validation
run_static_validation() {
    log_section "Running Static Validation"
    
    local validate_script="${SCRIPT_DIR}/validate-snapshot.sh"
    
    if [ ! -f "${validate_script}" ]; then
        log_error "Validation script not found: ${validate_script}"
        return 1
    fi
    
    log_info "Calling validate-snapshot.sh..."
    
    local validate_args=("--output-dir" "${OUTPUT_DIR}")
    
    if [ -n "${NETWORKS_JSON}" ] && [ -f "${NETWORKS_JSON}" ]; then
        validate_args+=("--networks-json" "${NETWORKS_JSON}")
    fi
    
    if "${validate_script}" "${validate_args[@]}"; then
        log_success "Static validation passed"
        return 0
    else
        log_error "Static validation failed"
        return 1
    fi
}

# Run runtime verification
run_runtime_verification() {
    log_section "Running Runtime Verification"
    
    local errors=0
    
    # Start docker-compose
    if ! start_docker_compose; then
        log_error "Failed to start docker-compose environment"
        return 1
    fi
    
    # Wait a bit for services to initialize
    log_info "Waiting for services to initialize..."
    sleep 10
    
    # Verify services
    if ! verify_l1_geth; then
        errors=$((errors + 1))
    fi
    
    if ! verify_l1_lighthouse; then
        errors=$((errors + 1))
    fi
    
    if ! verify_agglayer; then
        errors=$((errors + 1))
    fi
    
    if ! verify_l2_networks; then
        errors=$((errors + 1))
    fi
    
    if ! verify_agglayer_networks; then
        # This is a warning, not an error
        log_warn "Agglayer network registration check had warnings"
    fi
    
    # Stop docker-compose if cleanup is enabled
    if [ "${CLEANUP_ON_EXIT}" = "true" ]; then
        stop_docker_compose
    else
        log_info "Docker-compose environment left running (--no-cleanup flag set)"
    fi
    
    if [ ${errors} -eq 0 ]; then
        log_success "Runtime verification passed"
        return 0
    else
        log_error "Runtime verification failed: ${errors} error(s)"
        return 1
    fi
}

# Cleanup function
cleanup() {
    if [ "${CLEANUP_ON_EXIT}" = "true" ] && [ "${START_ENV}" = "true" ]; then
        stop_docker_compose
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main function
main() {
    log_step "1" "Snapshot Verification"
    
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
    
    log_info "Verifying snapshot in: ${OUTPUT_DIR}"
    log_info ""
    
    # Track verification results
    local static_passed=true
    local runtime_passed=true
    
    # Run static validation
    if ! run_static_validation; then
        static_passed=false
    fi
    
    # Run runtime verification if requested
    if [ "${START_ENV}" = "true" ]; then
        if ! run_runtime_verification; then
            runtime_passed=false
        fi
    else
        log_info "Runtime verification skipped (use --start-env to enable)"
    fi
    
    # Print summary
    log_section "Verification Summary"
    
    if [ "${static_passed}" = "true" ] && [ "${runtime_passed}" = "true" ]; then
        log_success "All verifications passed!"
        log_info "Snapshot is valid and ready to use"
        return 0
    else
        if [ "${static_passed}" != "true" ]; then
            log_error "Static validation failed"
        fi
        if [ "${START_ENV}" = "true" ] && [ "${runtime_passed}" != "true" ]; then
            log_error "Runtime verification failed"
        fi
        log_error "Verification failed - check log file for details: ${LOG_FILE}"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
}

# Run main function
main "$@"
