#!/bin/bash
# Generate docker-compose.yml from snapshot metadata
#
# This script:
# 1. Reads metadata from previous steps (configs, images, ports, networks)
# 2. Generates service configurations for L1, Agglayer, and all L2 networks
# 3. Creates final docker-compose.yml file
#
# IMPORTANT: Fresh-Start Design for L2 Services
# ==============================================
# All L2 services (CDK-Erigon, OP-Geth, OP-Node, AggKit, etc.) are
# configured to start with EMPTY data volumes. This is intentional:
#
# - L1 services use captured state from the snapshot (geth and lighthouse datadirs)
# - L2 services start fresh and perform initial sync from L1 on first run
# - This keeps snapshots smaller and simpler (no L2 state is captured)
# - Services will automatically sync from L1 when they start for the first time
#
# The sync time depends on L1 state size but is a one-time operation.
# Subsequent starts will be faster as services use their synced state.

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"
TEMPLATES_DIR="${SCRIPT_DIR}/../templates"

# Source utility functions
source "${UTILS_DIR}/logging.sh"
source "${UTILS_DIR}/prerequisites.sh"
source "${UTILS_DIR}/validation.sh"
source "${UTILS_DIR}/compose-generator.sh"

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2
EXIT_CODE_PREREQ_ERROR=3

# Default values
OUTPUT_DIR=""
AGGLAYER_IMAGE="europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer:0.4.4-remove-agglayer-prover"
AGGKIT_IMAGE="ghcr.io/agglayer/aggkit:0.8.0-beta7"
BRIDGE_IMAGE="ghcr.io/0xpolygon/zkevm-bridge-service:latest"
CDK_ERIGON_IMAGE="ghcr.io/0xpolygon/cdk-erigon:v2.61.24"
ZKEVM_PROVER_IMAGE="ghcr.io/0xpolygon/zkevm-prover:latest"
POOL_MANAGER_IMAGE="ghcr.io/0xpolygon/zkevm-pool-manager:latest"
DAC_IMAGE="ghcr.io/0xpolygon/cdk-data-availability:0.0.13"
OP_GETH_IMAGE="us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101605.0"
OP_NODE_IMAGE="us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.16.5"
OP_PROPOSER_IMAGE="ghcr.io/agglayer/op-succinct/op-succinct-agglayer:v3.4.0-rc.1-agglayer"
SP1_PROVER_KEY=""

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Generate docker-compose.yml from snapshot metadata.

Options:
    --output-dir DIR          Output directory from previous steps (required)
    --agglayer-image IMAGE    Agglayer image (default: from constants)
    --aggkit-image IMAGE      AggKit image (default: from constants)
    --bridge-image IMAGE      Bridge image (default: from constants)
    --cdk-erigon-image IMAGE  CDK-Erigon image (default: from constants)
    --zkevm-prover-image IMAGE ZKEVM Prover image (default: from constants)
    --pool-manager-image IMAGE Pool Manager image (default: from constants)
    --dac-image IMAGE         DAC image (default: from constants)
    --op-geth-image IMAGE     OP-Geth image (default: from constants)
    --op-node-image IMAGE     OP-Node image (default: from constants)
    --op-proposer-image IMAGE OP-Proposer image (default: from constants)
    --sp1-prover-key KEY      SP1 prover key (optional)
    -h, --help                Show this help message

Example:
    $0 \\
        --output-dir ./snapshot-output \\
        --agglayer-image ghcr.io/agglayer/agglayer:0.4.4
EOF
    exit 1
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --agglayer-image)
                AGGLAYER_IMAGE="$2"
                shift 2
                ;;
            --aggkit-image)
                AGGKIT_IMAGE="$2"
                shift 2
                ;;
            --bridge-image)
                BRIDGE_IMAGE="$2"
                shift 2
                ;;
            --cdk-erigon-image)
                CDK_ERIGON_IMAGE="$2"
                shift 2
                ;;
            --zkevm-prover-image)
                ZKEVM_PROVER_IMAGE="$2"
                shift 2
                ;;
            --pool-manager-image)
                POOL_MANAGER_IMAGE="$2"
                shift 2
                ;;
            --dac-image)
                DAC_IMAGE="$2"
                shift 2
                ;;
            --op-geth-image)
                OP_GETH_IMAGE="$2"
                shift 2
                ;;
            --op-node-image)
                OP_NODE_IMAGE="$2"
                shift 2
                ;;
            --op-proposer-image)
                OP_PROPOSER_IMAGE="$2"
                shift 2
                ;;
            --sp1-prover-key)
                SP1_PROVER_KEY="$2"
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
}

# Read metadata files
read_metadata() {
    local config_manifest="${OUTPUT_DIR}/config-processing-manifest.json"
    local l1_manifest="${OUTPUT_DIR}/l1-images/manifest.json"
    local port_mapping_file="${OUTPUT_DIR}/port-mapping.json"
    local keystore_mapping_file="${OUTPUT_DIR}/keystore-mapping.json"
    
    if [ ! -f "${config_manifest}" ]; then
        echo "Error: Config processing manifest not found: ${config_manifest}" >&2
        exit 1
    fi
    
    if [ ! -f "${l1_manifest}" ]; then
        echo "Error: L1 image manifest not found: ${l1_manifest}" >&2
        exit 1
    fi
    
    # Read metadata
    if command -v jq &> /dev/null; then
        PROCESSED_NETWORKS=$(jq -c '.processed_networks // []' "${config_manifest}" 2>/dev/null || echo "[]")
        PORT_MAPPING=$(jq -c '.port_mapping // {}' "${port_mapping_file}" 2>/dev/null || echo "{}")
        KEYSTORE_MAPPING=$(jq -c '.keystore_mapping // {}' "${keystore_mapping_file}" 2>/dev/null || echo "{}")
        
        # L1 metadata
        L1_GETH_IMAGE=$(jq -r '.geth.image_tag // "l1-geth:snapshot"' "${l1_manifest}" 2>/dev/null || echo "l1-geth:snapshot")
        L1_LIGHTHOUSE_IMAGE=$(jq -r '.lighthouse.image_tag // "l1-lighthouse:snapshot"' "${l1_manifest}" 2>/dev/null || echo "l1-lighthouse:snapshot")
        # Handle empty string for chain_id
        L1_CHAIN_ID=$(jq -r '.chain_id // "271828"' "${l1_manifest}" 2>/dev/null || echo "271828")
        if [ -z "${L1_CHAIN_ID}" ] || [ "${L1_CHAIN_ID}" = "null" ]; then
            L1_CHAIN_ID="271828"
        fi
        L1_LOG_FORMAT=$(jq -r '.log_format // "json"' "${l1_manifest}" 2>/dev/null || echo "json")
    else
        echo "Warning: jq not available, using defaults" >&2
        PROCESSED_NETWORKS="[]"
        PORT_MAPPING="{}"
        KEYSTORE_MAPPING="{}"
        L1_GETH_IMAGE="l1-geth:snapshot"
        L1_LIGHTHOUSE_IMAGE="l1-lighthouse:snapshot"
        L1_CHAIN_ID="271828"
        L1_LOG_FORMAT="json"
    fi
}

# Get port for network
get_port() {
    local network_id="$1"
    local port_key="$2"
    local default_port="$3"

    if command -v jq &> /dev/null && [ -n "${PORT_MAPPING}" ] && [ "${PORT_MAPPING}" != "null" ] && [ "${PORT_MAPPING}" != "{}" ]; then
        local port=$(echo "${PORT_MAPPING}" | jq -r ".[\"${network_id}\"].${port_key} // ${default_port}" 2>/dev/null || echo "${default_port}")
        echo "${port}"
    else
        # Apply offset to avoid L1/L2 port conflicts
        # L1 uses 8545-8547, L2 starts from 9545+ (offset of 1000)
        local port_with_offset=$((default_port + 1000))
        echo "${port_with_offset}"
    fi
}

# Generate L1 services
generate_l1_services() {
    local geth_datadir="${OUTPUT_DIR}/l1-state/geth"
    local lighthouse_datadir="${OUTPUT_DIR}/l1-state/lighthouse"
    
    if [ ! -d "${geth_datadir}" ]; then
        echo "Error: Geth datadir not found: ${geth_datadir}" >&2
        exit 1
    fi
    
    if [ ! -d "${lighthouse_datadir}" ]; then
        echo "Error: Lighthouse datadir not found: ${lighthouse_datadir}" >&2
        exit 1
    fi
    
    # Convert to absolute paths
    geth_datadir=$(cd "${geth_datadir}" && pwd)
    lighthouse_datadir=$(cd "${lighthouse_datadir}" && pwd)
    
    generate_l1_geth_service "${L1_GETH_IMAGE}" "${L1_CHAIN_ID}" "${L1_LOG_FORMAT}" "${geth_datadir}"
    echo ""
    generate_l1_lighthouse_service "${L1_LIGHTHOUSE_IMAGE}" "${L1_LOG_FORMAT}" "${lighthouse_datadir}" "l1-geth"
    echo ""

    # Add validator service if validator keys are present
    # ethereum-package stores validator keys in keys/ directory (not validator_definitions.yml)
    local validator_keys_dir="${OUTPUT_DIR}/l1-state/validator-keys"
    if [ -d "${validator_keys_dir}/keys" ] && [ "$(ls -A ${validator_keys_dir}/keys 2>/dev/null)" ]; then
        log_info "Validator keys found, adding validator service"
        # Convert log format to uppercase for Lighthouse (expects JSON not json)
        local lighthouse_log_format=$(echo "${L1_LOG_FORMAT}" | tr '[:lower:]' '[:upper:]')
        generate_l1_validator_service "${L1_LIGHTHOUSE_IMAGE}" "${lighthouse_log_format}" "http://l1-lighthouse:4000"
    else
        log_warn "No validator keys found, validator service will not be added"
        log_warn "L1 will not produce new blocks"
    fi
}

# Generate Agglayer service
generate_agglayer_service_config() {
    local agglayer_config="${OUTPUT_DIR}/configs/agglayer/config.toml"
    local keystore_dir=$(echo "${KEYSTORE_MAPPING}" | jq -r '.["1"] // .[to_entries[0].key] // ""' 2>/dev/null || echo "")
    
    if [ -z "${keystore_dir}" ]; then
        # Try to find first network's keystore
        if command -v jq &> /dev/null && [ -n "${PROCESSED_NETWORKS}" ] && [ "${PROCESSED_NETWORKS}" != "[]" ]; then
            local first_network_id=$(echo "${PROCESSED_NETWORKS}" | jq -r '.[0].network_id // "1"' 2>/dev/null || echo "1")
            keystore_dir="${OUTPUT_DIR}/keystores/${first_network_id}"
        else
            keystore_dir="${OUTPUT_DIR}/keystores/1"
        fi
    fi
    
    local aggregator_keystore="${keystore_dir}/aggregator.keystore"
    
    if [ ! -f "${agglayer_config}" ]; then
        echo "Error: Agglayer config not found: ${agglayer_config}" >&2
        exit 1
    fi
    
    if [ ! -f "${aggregator_keystore}" ]; then
        echo "Warning: Aggregator keystore not found: ${aggregator_keystore}" >&2
    fi
    
    # Convert to relative paths from docker-compose location
    local compose_dir=$(cd "${OUTPUT_DIR}" && pwd)
    agglayer_config="./configs/agglayer/config.toml"
    aggregator_keystore="./keystores/$(basename "${keystore_dir}")/aggregator.keystore"
    
    generate_agglayer_service "${AGGLAYER_IMAGE}" "${agglayer_config}" "${aggregator_keystore}" "${SP1_PROVER_KEY}"
}

# Generate network services
generate_network_services() {
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required for network service generation" >&2
        exit 1
    fi
    
    if [ -z "${PROCESSED_NETWORKS}" ] || [ "${PROCESSED_NETWORKS}" = "[]" ]; then
        echo "Warning: No processed networks found" >&2
        return
    fi
    
    local network_count=$(echo "${PROCESSED_NETWORKS}" | jq 'length' 2>/dev/null || echo "0")
    
    for ((i=0; i<network_count; i++)); do
        local network=$(echo "${PROCESSED_NETWORKS}" | jq -r ".[${i}]" 2>/dev/null)
        if [ -z "${network}" ] || [ "${network}" = "null" ]; then
            continue
        fi
        
        local network_id=$(echo "${network}" | jq -r '.network_id // ""' 2>/dev/null || echo "")
        local sequencer_type=$(echo "${network}" | jq -r '.sequencer_type // ""' 2>/dev/null || echo "")
        local consensus_type=$(echo "${network}" | jq -r '.consensus_type // ""' 2>/dev/null || echo "")
        local http_rpc_port=$(echo "${network}" | jq -r '.http_rpc_port // 8123' 2>/dev/null || echo "8123")
        
        if [ -z "${network_id}" ]; then
            echo "Warning: Skipping network ${i} (missing network_id)" >&2
            continue
        fi
        
        local config_dir_abs="${OUTPUT_DIR}/configs/${network_id}"
        local keystore_dir_abs="${OUTPUT_DIR}/keystores/${network_id}"

        # Convert to relative paths
        local config_dir="./configs/${network_id}"
        local keystore_dir="./keystores/${network_id}"

        if [ "${sequencer_type}" = "cdk-erigon" ]; then
            # CDK-Erigon services
            local erigon_http_port=$(get_port "${network_id}" "l2_rpc_http" "8123")
            local erigon_ws_port=$((erigon_http_port + 1))
            
            # RPC service uses different host ports to avoid conflict
            local erigon_rpc_http_port=$((erigon_http_port + 100))
            local erigon_rpc_ws_port=$((erigon_rpc_http_port + 1))
            
            generate_cdk_erigon_sequencer_service "${network_id}" "${CDK_ERIGON_IMAGE}" "${config_dir}" "${erigon_http_port}" "${erigon_ws_port}"
            echo ""
            
            generate_cdk_erigon_rpc_service "${network_id}" "${CDK_ERIGON_IMAGE}" "${config_dir}" "${erigon_rpc_http_port}" "${erigon_rpc_ws_port}"
            echo ""

            # AggKit (for all consensus types in snapshot)
            if [ "${consensus_type}" = "rollup" ] || [ "${consensus_type}" = "cdk-validium" ] || [ "${consensus_type}" = "pessimistic" ] || [ "${consensus_type}" = "ecdsa-multisig" ]; then
                # CDK-Erigon with rollup/cdk-validium uses PolygonZkEVMGlobalExitRootL2 (supports aggoracle)
                # CDK-Erigon with pessimistic/ecdsa-multisig uses LegacyAgglayerGERL2 (aggoracle not supported)
                local aggkit_components="aggsender,aggoracle"
                if [ "${consensus_type}" = "pessimistic" ] || [ "${consensus_type}" = "ecdsa-multisig" ]; then
                    aggkit_components="aggsender"
                fi
                local aggkit_depends="cdk-erigon-rpc-${network_id}"
                generate_aggkit_service "${network_id}" "${AGGKIT_IMAGE}" \
                    "${config_dir}/aggkit-config.toml" \
                    "${keystore_dir}" \
                    "${aggkit_components}" \
                    "${aggkit_depends}"
                echo ""
            fi
            
            # Bridge (for pessimistic, ecdsa-multisig)
            if [ "${consensus_type}" = "pessimistic" ] || [ "${consensus_type}" = "ecdsa-multisig" ]; then
                if [ -f "${OUTPUT_DIR}/configs/${network_id}/bridge-config.toml" ]; then
                    local bridge_rpc_port=$(get_port "${network_id}" "bridge_rpc" "8080")
                    local bridge_grpc_port=$(get_port "${network_id}" "bridge_grpc" "9090")
                    local bridge_metrics_port=$(get_port "${network_id}" "bridge_metrics" "8090")
                    
                    generate_bridge_service "${network_id}" "${BRIDGE_IMAGE}" \
                        "${config_dir}/bridge-config.toml" \
                        "${keystore_dir}/claimsponsor.keystore" \
                        "${bridge_rpc_port}" \
                        "${bridge_grpc_port}" \
                        "${bridge_metrics_port}"
                    echo ""
                fi
            fi
            
            # ZKEVM Prover (if config exists)
            if [ -f "${OUTPUT_DIR}/configs/${network_id}/zkevm-prover-config.json" ]; then
                local prover_hash_db_port=$(get_port "${network_id}" "prover_hash_db" "50061")
                local prover_executor_port=$(get_port "${network_id}" "prover_executor" "50071")
                
                generate_zkevm_prover_service "${network_id}" "${ZKEVM_PROVER_IMAGE}" \
                    "${config_dir}/zkevm-prover-config.json" \
                    "${prover_hash_db_port}" \
                    "${prover_executor_port}"
                echo ""
            fi
            
            # Pool Manager (for CDK-Erigon)
            if [ -f "${OUTPUT_DIR}/configs/${network_id}/pool-manager-config.toml" ]; then
                local pool_manager_port=$(get_port "${network_id}" "pool_manager" "8545")
                
                generate_pool_manager_service "${network_id}" "${POOL_MANAGER_IMAGE}" \
                    "${config_dir}/pool-manager-config.toml" \
                    "${pool_manager_port}"
                echo ""
            fi
            
            # DAC (for Validium)
            if [ "${consensus_type}" = "cdk-validium" ]; then
                if [ -f "${OUTPUT_DIR}/configs/${network_id}/dac-config.toml" ]; then
                    local dac_port=$(get_port "${network_id}" "dac" "8080")
                    
                    generate_dac_service "${network_id}" "${DAC_IMAGE}" \
                        "${config_dir}/dac-config.toml" \
                        "${dac_port}"
                    echo ""
                fi
            fi
            
        elif [ "${sequencer_type}" = "op-geth" ]; then
            # OP-Geth services
            local op_geth_http_port=$(get_port "${network_id}" "l2_rpc_http" "8545")
            local op_geth_ws_port=$((op_geth_http_port + 1))
            # OP-Node uses a separate port (internal 8547) - external port is +2 from op-geth http
            local op_node_rpc_port=$((op_geth_http_port + 2))

            # Extract L2 chain ID from rollup.json using absolute path
            local l2_chain_id=$(jq -r '.l2_chain_id' "${config_dir_abs}/rollup.json")

            generate_op_geth_service "${network_id}" "${OP_GETH_IMAGE}" \
                "${config_dir}" \
                "${config_dir}/genesis.json" \
                "${op_geth_http_port}" \
                "${op_geth_ws_port}" \
                "${l2_chain_id}"
            echo ""

            generate_op_node_service "${network_id}" "${OP_NODE_IMAGE}" \
                "${config_dir}/op-node-config.toml" \
                "${op_node_rpc_port}"
            echo ""
            
            # OP-Proposer (for OP-Succinct/FEP)
            if [ "${consensus_type}" = "fep" ]; then
                local op_proposer_grpc_port=$(get_port "${network_id}" "op_proposer_grpc" "50051")
                local op_proposer_metrics_port=$(get_port "${network_id}" "op_proposer_metrics" "8080")
                
                generate_op_proposer_service "${network_id}" "${OP_PROPOSER_IMAGE}" \
                    "${config_dir}/genesis.json" \
                    "${op_proposer_grpc_port}" \
                    "${op_proposer_metrics_port}"
                echo ""
            fi
            
            # AggKit (for OP-Geth)
            if [ "${consensus_type}" = "pessimistic" ] || [ "${consensus_type}" = "ecdsa-multisig" ] || [ "${consensus_type}" = "fep" ]; then
                # TODO: OP-Geth uses GlobalExitRootManagerL2SovereignChain which supports aggoracle,
                # but we need to extract the correct L2 bridge address from the enclave first.
                # For now, only use aggsender in snapshots.
                local aggkit_components="aggsender"
                local aggkit_depends="op-node-${network_id}"
                generate_aggkit_service "${network_id}" "${AGGKIT_IMAGE}" \
                    "${config_dir}/aggkit-config.toml" \
                    "${keystore_dir}" \
                    "${aggkit_components}" \
                    "${aggkit_depends}"
                echo ""
            fi
            
            # Bridge (for OP-Geth with pessimistic/ecdsa-multisig)
            if [ "${consensus_type}" = "pessimistic" ] || [ "${consensus_type}" = "ecdsa-multisig" ]; then
                if [ -f "${OUTPUT_DIR}/configs/${network_id}/bridge-config.toml" ]; then
                    local bridge_rpc_port=$(get_port "${network_id}" "bridge_rpc" "8080")
                    local bridge_grpc_port=$(get_port "${network_id}" "bridge_grpc" "9090")
                    local bridge_metrics_port=$(get_port "${network_id}" "bridge_metrics" "8090")
                    
                    generate_bridge_service "${network_id}" "${BRIDGE_IMAGE}" \
                        "${config_dir}/bridge-config.toml" \
                        "${keystore_dir}/claimsponsor.keystore" \
                        "${bridge_rpc_port}" \
                        "${bridge_grpc_port}" \
                        "${bridge_metrics_port}"
                    echo ""
                fi
            fi
        fi
    done
}

# Generate volumes section
# Note: All volumes are intentionally empty (named volumes without initialization).
# L2 services will sync from L1 on first run - see header comments for details.
generate_volumes_section() {
    if ! command -v jq &> /dev/null; then
        return
    fi
    
    if [ -z "${PROCESSED_NETWORKS}" ] || [ "${PROCESSED_NETWORKS}" = "[]" ]; then
        return
    fi
    
    local network_ids=$(echo "${PROCESSED_NETWORKS}" | jq -r '.[].network_id' 2>/dev/null | sort -u | tr '\n' ' ')
    generate_volumes "${network_ids}"
}

# Validate docker-compose file
validate_compose() {
    local compose_file="${OUTPUT_DIR}/docker-compose.yml"
    
    if [ ! -f "${compose_file}" ]; then
        echo "Error: Generated docker-compose.yml not found" >&2
        exit 1
    fi
    
    # Check if docker-compose is available
    if command -v docker-compose &> /dev/null; then
        echo "Validating docker-compose.yml syntax..."
        if docker-compose -f "${compose_file}" config > /dev/null 2>&1; then
            echo "✅ docker-compose.yml syntax is valid"
        else
            echo "⚠️  docker-compose.yml validation failed (continuing anyway)" >&2
        fi
    elif command -v docker &> /dev/null; then
        echo "Validating docker-compose.yml syntax..."
        if docker compose -f "${compose_file}" config > /dev/null 2>&1; then
            echo "✅ docker-compose.yml syntax is valid"
        else
            echo "⚠️  docker-compose.yml validation failed (continuing anyway)" >&2
        fi
    else
        echo "⚠️  docker-compose not available, skipping validation" >&2
    fi
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
}

# Set trap for cleanup
trap cleanup EXIT

# Main function
main() {
    log_step "1" "Docker Compose Generation"
    
    # Parse arguments
    parse_args "$@"
    
    # Setup logging
    setup_logging "${OUTPUT_DIR}" || {
        echo "Error: Failed to setup logging" >&2
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    
    # Check prerequisites
    log_section "Checking prerequisites"
    if ! check_docker; then
        log_error "Prerequisites check failed"
        exit ${EXIT_CODE_PREREQ_ERROR}
    fi
    
    if ! check_docker_compose; then
        log_error "docker-compose check failed"
        exit ${EXIT_CODE_PREREQ_ERROR}
    fi
    
    if ! check_jq; then
        log_error "jq is required for compose generation"
        exit ${EXIT_CODE_PREREQ_ERROR}
    fi
    
    if ! check_output_dir "${OUTPUT_DIR}"; then
        log_error "Output directory check failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    log_success "Prerequisites check passed"
    
    # Read metadata
    log_section "Reading metadata"
    read_metadata
    log_success "Metadata loaded"
    
    # Generate services
    echo "Generating service configurations..."
    
    # Generate L1 services
    echo "Generating L1 services..."
    L1_SERVICES=$(generate_l1_services)
    echo "✅ L1 services generated"
    echo ""
    
    # Generate Agglayer service
    echo "Generating Agglayer service..."
    AGGLAYER_SERVICE=$(generate_agglayer_service_config)
    echo "✅ Agglayer service generated"
    echo ""
    
    # Generate network services
    echo "Generating network services..."
    NETWORK_SERVICES=$(generate_network_services)
    echo "✅ Network services generated"
    echo ""
    
    # Generate volumes
    echo "Generating volumes..."
    VOLUMES=$(generate_volumes_section)
    echo "✅ Volumes generated"
    echo ""
    
    # Process template
    echo "Processing docker-compose template..."
    local output_file="${OUTPUT_DIR}/docker-compose.yml"
    
    # Write docker-compose.yml directly
    {
        echo "services:"
        echo "${L1_SERVICES}"
        echo ""
        echo "${AGGLAYER_SERVICE}"
        echo ""
        echo "${NETWORK_SERVICES}"
        echo ""
        echo "networks:"
        echo "  cdk-network:"
        echo "    driver: bridge"
        if [ -n "${VOLUMES}" ]; then
            echo ""
            echo "volumes:"
            echo "${VOLUMES}"
        fi
    } > "${output_file}"
    
    echo "✅ docker-compose.yml generated: ${output_file}"
    echo ""
    
    # Validate
    log_section "Validating docker-compose.yml"
    validate_compose
    
    # Additional validation
    if ! validate_docker_compose "${output_file}"; then
        log_error "Docker compose validation failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    log_success "Docker compose validated"
    
    log_section "Summary"
    log_info "Output: ${output_file}"
    
    log_success "Docker Compose Generation Complete"
}

# Run main function
main "$@"
