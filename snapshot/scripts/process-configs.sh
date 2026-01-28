#!/bin/bash
# Process extracted config artifacts from Kurtosis to static docker-compose format
#
# This script:
# 1. Downloads artifacts from Kurtosis enclave
# 2. Processes each network's config files (converting service names/URLs)
# 3. Updates agglayer config with all networks
# 4. Creates port and keystore mappings

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"
source "${UTILS_DIR}/prerequisites.sh"
source "${UTILS_DIR}/validation.sh"
source "${UTILS_DIR}/config-processor.sh"

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2
EXIT_CODE_PREREQ_ERROR=3

# Default values
ENCLAVE_NAME=""
OUTPUT_DIR=""
ARTIFACT_MANIFEST=""
NETWORKS_JSON=""
TEMP_DIR=""

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Process extracted config artifacts from Kurtosis to static docker-compose format.

Options:
    --enclave-name NAME       Kurtosis enclave name (required)
    --output-dir DIR          Output directory for processed configs (required)
    --artifact-manifest FILE  Path to artifact manifest JSON (optional, will try to infer from Kurtosis)
    --networks-json FILE      Path to networks configuration JSON (optional, will try to infer)
    -h, --help                Show this help message

Example:
    $0 \\
        --enclave-name snapshot \\
        --output-dir ./snapshot-output \\
        --artifact-manifest ./artifact-manifest.json \\
        --networks-json ./networks.json
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
            --artifact-manifest)
                ARTIFACT_MANIFEST="$2"
                shift 2
                ;;
            --networks-json)
                NETWORKS_JSON="$2"
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

# Download artifact from Kurtosis
# Usage: download_artifact <artifact_name> <dest_dir>
download_artifact() {
    local artifact_name="$1"
    local dest_dir="$2"
    
    echo "Downloading artifact: ${artifact_name}..."
    
    mkdir -p "${dest_dir}"
    
    if kurtosis files download "${ENCLAVE_NAME}" "${artifact_name}" "${dest_dir}" 2>/dev/null; then
        echo "✅ Downloaded ${artifact_name}"
        return 0
    else
        echo "⚠️  Artifact ${artifact_name} not found (may be optional)"
        return 1
    fi
}

# Process AggKit config
# Usage: process_aggkit_config <input_file> <output_file> <deployment_suffix> <network_id> <l2_rpc_name> <http_rpc_port>
process_aggkit_config() {
    local input_file="$1"
    local output_file="$2"
    local deployment_suffix="$3"
    local network_id="$4"
    local l2_rpc_name="$5"
    local http_rpc_port="${6:-8123}"
    
    if [ ! -f "${input_file}" ]; then
        echo "Warning: AggKit config not found: ${input_file}"
        return 0
    fi
    
    echo "Processing AggKit config for network ${network_id}..."
    
    local config_content
    config_content=$(read_toml_file "${input_file}")
    
    # Convert service URLs
    config_content=$(replace_urls_in_config "${config_content}" "${deployment_suffix}" "${network_id}")
    
    # Replace L1 RPC URL to use docker-compose service name
    # Match various L1 URL patterns in the config
    config_content=$(echo "${config_content}" | sed "s|L1URL=\"http://[^\"]*\"|L1URL=\"http://l1-geth:8545\"|g")
    config_content=$(echo "${config_content}" | sed "s|L1URL = \"http://[^\"]*\"|L1URL = \"http://l1-geth:8545\"|g")
    config_content=$(echo "${config_content}" | sed "s|l1_rpc_url = \"http://[^\"]*\"|l1_rpc_url = \"http://l1-geth:8545\"|g")
    # Replace L1Config.URL field (catches el-1-geth-lighthouse or similar L1 service names)
    config_content=$(echo "${config_content}" | sed "s|URL = \"http://.*el-1-geth[^\"]*:8545\"|URL = \"http://l1-geth:8545\"|g")
    config_content=$(echo "${config_content}" | sed "s|URL = \"http://.*lighthouse[^\"]*:8545\"|URL = \"http://l1-geth:8545\"|g")
    
    # Replace L2 URL (use internal port 8545, not external port mapping)
    config_content=$(echo "${config_content}" | sed "s|L2URL[[:space:]]*=[[:space:]]*\"http://[^\"]*\"|L2URL = \"http://${l2_rpc_name}-${network_id}:8545\"|g")
    
    # Replace agglayer URL
    config_content=$(echo "${config_content}" | sed "s|AggLayerURL=\"http://[^\"]*\"|AggLayerURL=\"http://agglayer:8080\"|g")
    config_content=$(echo "${config_content}" | sed "s|AggLayerURL=\"grpc://[^\"]*\"|AggLayerURL=\"grpc://agglayer:50081\"|g")

    # Note: No database URL replacement needed. AggKit uses SQLite for storage (not PostgreSQL).
    # SQLite databases are stored in local file paths configured in the AggKit config.

    # Ensure all Ethereum addresses have 0x prefix
    # Match 40-char hex strings that don't already start with "0x"
    # First pass: handle field = "ADDRESS" pattern
    config_content=$(echo "${config_content}" | perl -pe 's/((?:Addr|Address)[[:space:]]*=[[:space:]]*)"(?!0x)([0-9a-fA-F]{40})"/\1"0x\2"/g')
    # Second pass: catch any remaining 40-char hex without 0x prefix in quoted strings
    config_content=$(echo "${config_content}" | perl -pe 's/="(?!0x)([0-9a-fA-F]{40})"/="0x\1"/g')

    write_toml_file "${output_file}" "${config_content}"
    
    # Validate
    if validate_toml "${output_file}"; then
        echo "✅ AggKit config processed successfully"
    else
        echo "⚠️  AggKit config validation warning (continuing anyway)"
    fi
}

# Process bridge config (if exists)
# Usage: process_bridge_config <input_file> <output_file> <deployment_suffix> <network_id>
process_bridge_config() {
    local input_file="$1"
    local output_file="$2"
    local deployment_suffix="$3"
    local network_id="$4"
    
    if [ ! -f "${input_file}" ]; then
        echo "Warning: Bridge config not found: ${input_file}"
        return 0
    fi
    
    echo "Processing bridge config for network ${network_id}..."
    
    # Bridge configs are typically JSON
    if echo "${input_file}" | grep -q "\.json$"; then
        local config_content
        config_content=$(read_json_file "${input_file}")
        
        # Convert service URLs in JSON
        config_content=$(echo "${config_content}" | sed "s/\(http[s]*:\/\/[^:]*\)${deployment_suffix}\(:[0-9]*\)/\1-${network_id}\2/g")
        
        # Replace L1 RPC URL to use docker-compose service name
        config_content=$(echo "${config_content}" | sed "s|\"http://[^\"]*el-1-geth[^\"]*:8545\"|\"http://l1-geth:8545\"|g")
        config_content=$(echo "${config_content}" | sed "s|\"l1_rpc_url\":\"http://[^\"]*\"|\"l1_rpc_url\":\"http://l1-geth:8545\"|g")

        # Ensure all Ethereum addresses have 0x prefix in JSON
        config_content=$(echo "${config_content}" | sed -E 's/("[^"]*[Aa]ddr[^"]*":"[[:space:]]*)([0-9a-fA-F]{40})"/\10x\2"/g')
        config_content=$(echo "${config_content}" | sed -E 's/("[^"]*[Aa]ddress[^"]*":"[[:space:]]*)([0-9a-fA-F]{40})"/\10x\2"/g')

        write_json_file "${output_file}" "${config_content}"
        
        # Validate
        if validate_json "${output_file}"; then
            echo "✅ Bridge config processed successfully"
        else
            echo "⚠️  Bridge config validation warning (continuing anyway)"
        fi
    else
        # TOML format
        local config_content
        config_content=$(read_toml_file "${input_file}")
        config_content=$(replace_urls_in_config "${config_content}" "${deployment_suffix}" "${network_id}")
        
        # Replace L1 RPC URL to use docker-compose service name
        config_content=$(echo "${config_content}" | sed "s|L1URL=\"http://[^\"]*\"|L1URL=\"http://l1-geth:8545\"|g")
        config_content=$(echo "${config_content}" | sed "s|L1URL = \"http://[^\"]*\"|L1URL = \"http://l1-geth:8545\"|g")
        config_content=$(echo "${config_content}" | sed "s|l1_rpc_url = \"http://[^\"]*\"|l1_rpc_url = \"http://l1-geth:8545\"|g")

        # Ensure all Ethereum addresses have 0x prefix in TOML
        config_content=$(echo "${config_content}" | sed -E 's/(Addr[[:space:]]*=[[:space:]]*)"([0-9a-fA-F]{40})"/\1"0x\2"/g')
        config_content=$(echo "${config_content}" | sed -E 's/(Address[[:space:]]*=[[:space:]]*)"([0-9a-fA-F]{40})"/\1"0x\2"/g')

        write_toml_file "${output_file}" "${config_content}"
    fi
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
        log_debug "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}" || true
    fi
    if [ ${exit_code} -ne 0 ]; then
        log_error "Script failed with exit code ${exit_code}"
        if [ -n "${LOG_FILE}" ]; then
            log_error "Check log file for details: ${LOG_FILE}"
        fi
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main processing function
main() {
    log_step "1" "Config Processing for Snapshot"
    
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
    
    if ! check_jq; then
        log_error "jq is required for config processing"
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
    mkdir -p "${OUTPUT_DIR}/configs" || {
        log_error "Failed to create configs directory"
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    mkdir -p "${OUTPUT_DIR}/keystores" || {
        log_error "Failed to create keystores directory"
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    TEMP_DIR=$(mktemp -d) || {
        log_error "Failed to create temporary directory"
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    
    log_info "Enclave: ${ENCLAVE_NAME}"
    log_info "Output directory: ${OUTPUT_DIR}"
    log_debug "Temporary directory: ${TEMP_DIR}"
    
    # Try to get artifact list from Kurtosis if manifest not provided
    if [ -z "${ARTIFACT_MANIFEST}" ]; then
        echo "Attempting to list artifacts from Kurtosis enclave..."
        # Note: Kurtosis may not have a direct command to list artifacts
        # We'll need to try downloading known artifact names
        ARTIFACT_MANIFEST="${TEMP_DIR}/artifact-manifest.json"
        echo "{}" > "${ARTIFACT_MANIFEST}"
    fi
    
    # Load networks configuration
    log_section "Loading networks configuration"
    local networks_data="[]"
    if [ -n "${NETWORKS_JSON}" ] && [ -f "${NETWORKS_JSON}" ]; then
        # Validate networks JSON
        if ! validate_config_file "${NETWORKS_JSON}" "json"; then
            log_error "Invalid networks JSON file"
            exit ${EXIT_CODE_VALIDATION_ERROR}
        fi
        
        # Validate network configs
        if ! validate_networks_config "${NETWORKS_JSON}"; then
            log_error "Network configuration validation failed"
            exit ${EXIT_CODE_VALIDATION_ERROR}
        fi
        
        # Extract networks array (handle both {"networks": [...]} and [...] formats)
        networks_data=$(jq -c '.networks // .' "${NETWORKS_JSON}" 2>/dev/null || echo "[]")
        log_success "Networks configuration loaded and validated"
    else
        log_warn "Networks JSON not provided, will try to infer from artifacts"
    fi
    
    # Extract network information from networks_data
    local network_count=0
    if command -v jq &> /dev/null && [ "${networks_data}" != "[]" ]; then
        network_count=$(echo "${networks_data}" | jq 'length' 2>/dev/null || echo "0")
    fi
    
    log_info "Processing ${network_count} network(s)..."
    
    # Process each network
    local processed_networks="[]"
    local port_mapping="{}"
    local keystore_mapping="{}"
    
    # Initialize port allocation
    # Default ports per service type
    local base_l1_geth_http=8545
    local base_l1_geth_ws=8546
    local base_l1_lighthouse=4000
    local base_agglayer_readrpc=8080
    local base_agglayer_grpc=50081
    local base_cdk_erigon_rpc=8123
    local base_aggkit_aggregator=50082
    
    if [ "${network_count}" -gt 0 ] && command -v jq &> /dev/null; then
        for i in $(seq 0 $((network_count - 1))); do
            local network_id
            network_id=$(echo "${networks_data}" | jq -r ".[${i}].network_id" 2>/dev/null || echo "")
            local deployment_suffix
            deployment_suffix=$(echo "${networks_data}" | jq -r ".[${i}].deployment_suffix // \"\"" 2>/dev/null || echo "")
            local sequencer_type
            sequencer_type=$(echo "${networks_data}" | jq -r ".[${i}].sequencer_type" 2>/dev/null || echo "")
            local l2_rpc_name
            l2_rpc_name=$(echo "${networks_data}" | jq -r ".[${i}].l2_rpc_name" 2>/dev/null || echo "")
            # Set default l2_rpc_name based on sequencer type if not provided
            if [ -z "${l2_rpc_name}" ] || [ "${l2_rpc_name}" = "null" ]; then
                if [ "${sequencer_type}" = "cdk-erigon" ]; then
                    l2_rpc_name="cdk-erigon-rpc"
                elif [ "${sequencer_type}" = "op-geth" ]; then
                    l2_rpc_name="op-el"
                else
                    l2_rpc_name="cdk-erigon-rpc"  # Default fallback
                fi
            fi
            local http_rpc_port
            http_rpc_port=$(echo "${networks_data}" | jq -r ".[${i}].http_rpc_port // 8123" 2>/dev/null || echo "8123")
            local l2_chain_id
            l2_chain_id=$(echo "${networks_data}" | jq -r ".[${i}].l2_chain_id // 20201" 2>/dev/null || echo "20201")
            local l2_sequencer_address
            l2_sequencer_address=$(echo "${networks_data}" | jq -r ".[${i}].l2_sequencer_address" 2>/dev/null || echo "")
            
            if [ -z "${network_id}" ] || [ "${network_id}" = "null" ]; then
                echo "Warning: Skipping network ${i} (missing network_id)"
                continue
            fi
            
            echo "----------------------------------------"
            echo "Processing network ${network_id} (suffix: ${deployment_suffix})"
            echo "----------------------------------------"
            
            # Create network output directory
            local network_output_dir="${OUTPUT_DIR}/configs/${network_id}"
            mkdir -p "${network_output_dir}"
            
            # Download and process artifacts for this network
            local artifact_base=""
            if [ -n "${deployment_suffix}" ]; then
                artifact_base="${deployment_suffix}"
            else
                artifact_base=""
            fi

            # Download CDK-Erigon sequencer config
            if [ "${sequencer_type}" = "cdk-erigon" ]; then
                local erigon_seq_config_artifact="cdk-erigon-sequencer-config${artifact_base}"
                local erigon_seq_config_dest="${TEMP_DIR}/${erigon_seq_config_artifact}"
                if download_artifact "${erigon_seq_config_artifact}" "${erigon_seq_config_dest}" 2>/dev/null; then
                    local erigon_seq_config_file
                    erigon_seq_config_file=$(find "${erigon_seq_config_dest}" -name "config.yaml" -type f | head -1 || echo "")
                    if [ -n "${erigon_seq_config_file}" ]; then
                        # Remove if it exists as a directory (from failed previous run)
                        if [ -d "${network_output_dir}/config.yaml" ]; then
                            rm -rf "${network_output_dir}/config.yaml"
                        fi
                        cp "${erigon_seq_config_file}" "${network_output_dir}/config.yaml"
                        # Post-process config.yaml to replace L1 RPC URL
                        sed -i 's|zkevm\.l1-rpc-url: http://[^:]*:[0-9]*|zkevm.l1-rpc-url: http://l1-geth:8545|g' "${network_output_dir}/config.yaml"
                        echo "✅ Copied and processed CDK-Erigon sequencer config.yaml"
                    fi
                fi

                # Download CDK-Erigon RPC config (same as sequencer for now, but keep separate artifacts)
                local erigon_rpc_config_artifact="cdk-erigon-rpc-config${artifact_base}"
                local erigon_rpc_config_dest="${TEMP_DIR}/${erigon_rpc_config_artifact}"
                if download_artifact "${erigon_rpc_config_artifact}" "${erigon_rpc_config_dest}" 2>/dev/null; then
                    # RPC uses same config as sequencer in docker-compose
                    echo "✅ Downloaded CDK-Erigon RPC config (using same config as sequencer)"
                fi
            fi

            # Download AggKit config
            local aggkit_artifact="aggkit-config${artifact_base}"
            local aggkit_dest="${TEMP_DIR}/${aggkit_artifact}"
            if download_artifact "${aggkit_artifact}" "${aggkit_dest}" 2>/dev/null; then
                local aggkit_config_file
                aggkit_config_file=$(find "${aggkit_dest}" -name "config.toml" -type f | head -1 || echo "")
                if [ -n "${aggkit_config_file}" ]; then
                    process_aggkit_config "${aggkit_config_file}" "${network_output_dir}/aggkit-config.toml" "${deployment_suffix}" "${network_id}" "${l2_rpc_name}" "${http_rpc_port}"
                fi
            fi
            
            # Download genesis
            local genesis_artifact="genesis${artifact_base}"
            local genesis_dest="${TEMP_DIR}/${genesis_artifact}"
            if download_artifact "${genesis_artifact}" "${genesis_dest}" 2>/dev/null; then
                local genesis_file
                genesis_file=$(find "${genesis_dest}" -name "genesis.json" -type f | head -1 || echo "")
                if [ -n "${genesis_file}" ]; then
                    # Remove if it exists as a directory (from failed previous run)
                    if [ -d "${network_output_dir}/genesis.json" ]; then
                        rm -rf "${network_output_dir}/genesis.json"
                    fi
                    cp "${genesis_file}" "${network_output_dir}/genesis.json"
                    echo "✅ Copied genesis.json"
                fi
            fi
            
            # Download chain configs (CDK-Erigon only)
            if [ "${sequencer_type}" = "cdk-erigon" ]; then
                local chain_config_artifact="cdk-erigon-chain-config${artifact_base}"
                local chain_config_dest="${TEMP_DIR}/${chain_config_artifact}"
                if download_artifact "${chain_config_artifact}" "${chain_config_dest}" 2>/dev/null; then
                    local chain_config_file
                    chain_config_file=$(find "${chain_config_dest}" -name "*.json" -type f | head -1 || echo "")
                    if [ -n "${chain_config_file}" ]; then
                        # Remove if it exists as a directory (from failed previous run)
                        if [ -d "${network_output_dir}/chain-config.json" ]; then
                            rm -rf "${network_output_dir}/chain-config.json"
                        fi
                        cp "${chain_config_file}" "${network_output_dir}/chain-config.json"
                        echo "✅ Copied chain-config.json"
                    fi
                fi
                
                local chain_allocs_artifact="cdk-erigon-chain-allocs${artifact_base}"
                local chain_allocs_dest="${TEMP_DIR}/${chain_allocs_artifact}"
                if download_artifact "${chain_allocs_artifact}" "${chain_allocs_dest}" 2>/dev/null; then
                    local chain_allocs_file
                    chain_allocs_file=$(find "${chain_allocs_dest}" -name "*.json" -type f | head -1 || echo "")
                    if [ -n "${chain_allocs_file}" ]; then
                        # Remove if it exists as a directory (from failed previous run)
                        if [ -d "${network_output_dir}/chain-allocs.json" ]; then
                            rm -rf "${network_output_dir}/chain-allocs.json"
                        fi
                        cp "${chain_allocs_file}" "${network_output_dir}/chain-allocs.json"
                        echo "✅ Copied chain-allocs.json"
                    fi
                fi
                
                local chain_first_batch_artifact="cdk-erigon-chain-first-batch${artifact_base}"
                local chain_first_batch_dest="${TEMP_DIR}/${chain_first_batch_artifact}"
                if download_artifact "${chain_first_batch_artifact}" "${chain_first_batch_dest}" 2>/dev/null; then
                    local chain_first_batch_file
                    chain_first_batch_file=$(find "${chain_first_batch_dest}" -name "*.json" -type f | head -1 || echo "")
                    if [ -n "${chain_first_batch_file}" ]; then
                        # Remove if it exists as a directory (from failed previous run)
                        if [ -d "${network_output_dir}/first-batch-config.json" ]; then
                            rm -rf "${network_output_dir}/first-batch-config.json"
                        fi
                        cp "${chain_first_batch_file}" "${network_output_dir}/first-batch-config.json"
                        echo "✅ Copied first-batch-config.json"
                    fi
                fi

                # Generate chainspec file for dynamic chain configuration
                # CDK-Erigon expects dynamic-<chain-name>-chainspec.json when using dynamic- prefix
                # Use flat format (not nested under "config") matching cdk-erigon expectations
                if [ -f "${network_output_dir}/chain-config.json" ]; then
                    local chainspec_file="${network_output_dir}/dynamic-kurtosis-chainspec.json"
                    # Create flat chainspec matching CDK-Erigon's expected format
                    jq -n --arg chainId "${l2_chain_id}" \
                        '{
                            "ChainName": "dynamic-kurtosis",
                            "chainId": ($chainId | tonumber),
                            "consensus": "ethash",
                            "homesteadBlock": 0,
                            "daoForkBlock": 0,
                            "eip150Block": 0,
                            "eip155Block": 0,
                            "byzantiumBlock": 0,
                            "constantinopleBlock": 0,
                            "petersburgBlock": 0,
                            "istanbulBlock": 0,
                            "muirGlacierBlock": 0,
                            "berlinBlock": 0,
                            "londonBlock": 0,
                            "arrowGlacierBlock": 9999999999999999999999999999999999999999999999999,
                            "grayGlacierBlock": 9999999999999999999999999999999999999999999999999,
                            "terminalTotalDifficultyPassed": false,
                            "shanghaiTime": 0,
                            "cancunTime": 0,
                            "normalcyBlock": 0,
                            "pragueTime": 0,
                            "ethash": {}
                        }' > "${chainspec_file}"
                    echo "✅ Generated dynamic-kurtosis-chainspec.json"

                    # Also copy chain-config.json as dynamic-kurtosis-conf.json
                    # CDK-Erigon expects this file for timestamp and other configurations
                    local conf_file="${network_output_dir}/dynamic-kurtosis-conf.json"
                    cp "${network_output_dir}/chain-config.json" "${conf_file}"
                    echo "✅ Generated dynamic-kurtosis-conf.json"

                    # Copy chain-allocs.json as dynamic-kurtosis-allocs.json
                    # CDK-Erigon expects this file for account allocations
                    if [ -f "${network_output_dir}/chain-allocs.json" ]; then
                        local allocs_file="${network_output_dir}/dynamic-kurtosis-allocs.json"
                        cp "${network_output_dir}/chain-allocs.json" "${allocs_file}"
                        echo "✅ Generated dynamic-kurtosis-allocs.json"
                    fi
                fi

                # Post-process CDK-Erigon config.yaml with required fields
                if [ -f "${network_output_dir}/config.yaml" ]; then
                    echo "Post-processing CDK-Erigon config.yaml..."

                    # Extract rollup address from aggkit config
                    local rollup_address=""
                    if [ -f "${network_output_dir}/aggkit-config.toml" ]; then
                        rollup_address=$(grep "^SovereignRollupAddr" "${network_output_dir}/aggkit-config.toml" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1)
                    fi

                    # Set zkevm.address-zkevm with rollup address
                    if [ -n "${rollup_address}" ]; then
                        sed -i "s|zkevm\.address-zkevm: \"<no value>\"|zkevm.address-zkevm: \"${rollup_address}\"|g" "${network_output_dir}/config.yaml"
                        sed -i "s|zkevm\.address-zkevm: \"\"|zkevm.address-zkevm: \"${rollup_address}\"|g" "${network_output_dir}/config.yaml"
                        echo "✅ Set zkevm.address-zkevm to ${rollup_address}"
                    fi

                    # Add L2 sequencer RPC URL and datastreamer URL for RPC nodes
                    # Check if these fields are missing or have placeholder values
                    if ! grep -q "zkevm\.l2-sequencer-rpc-url: \"http://" "${network_output_dir}/config.yaml"; then
                        # Insert after the address-zkevm line
                        sed -i "/zkevm\.address-zkevm:/a\\
\\
# The upstream L2 node RPC endpoint (for RPC nodes only).\\
# Default: \"\"\\
zkevm.l2-sequencer-rpc-url: \"http://cdk-erigon-sequencer-${network_id}:8545\"" "${network_output_dir}/config.yaml"
                        echo "✅ Added zkevm.l2-sequencer-rpc-url"
                    fi

                    if ! grep -q "zkevm\.l2-datastreamer-url:" "${network_output_dir}/config.yaml"; then
                        # Insert after l2-sequencer-rpc-url
                        sed -i "/zkevm\.l2-sequencer-rpc-url:/a\\
\\
# The upstream L2 datastreamer endpoint (for RPC nodes only).\\
# Default: \"\"\\
zkevm.l2-datastreamer-url: \"cdk-erigon-sequencer-${network_id}:6900\"" "${network_output_dir}/config.yaml"
                        echo "✅ Added zkevm.l2-datastreamer-url"
                    fi
                fi
            fi

            # Download keystores
            local keystore_dir="${OUTPUT_DIR}/keystores/${network_id}"
            mkdir -p "${keystore_dir}"
            
            local sequencer_keystore_artifact="sequencer-keystore${artifact_base}"
            local sequencer_keystore_dest="${TEMP_DIR}/${sequencer_keystore_artifact}"
            if download_artifact "${sequencer_keystore_artifact}" "${sequencer_keystore_dest}" 2>/dev/null; then
                local sequencer_keystore_file
                sequencer_keystore_file=$(find "${sequencer_keystore_dest}" -name "*.keystore" -type f | head -1 || echo "")
                if [ -n "${sequencer_keystore_file}" ]; then
                    # Remove if it exists as a directory (from failed previous run)
                    if [ -d "${keystore_dir}/sequencer.keystore" ]; then
                        rm -rf "${keystore_dir}/sequencer.keystore"
                    fi
                    cp "${sequencer_keystore_file}" "${keystore_dir}/sequencer.keystore"
                    echo "✅ Copied sequencer keystore"
                fi
            fi
            
            local aggregator_keystore_artifact="aggregator-keystore${artifact_base}"
            local aggregator_keystore_dest="${TEMP_DIR}/${aggregator_keystore_artifact}"
            if download_artifact "${aggregator_keystore_artifact}" "${aggregator_keystore_dest}" 2>/dev/null; then
                local aggregator_keystore_file
                aggregator_keystore_file=$(find "${aggregator_keystore_dest}" -name "*.keystore" -type f | head -1 || echo "")
                if [ -n "${aggregator_keystore_file}" ]; then
                    # Remove if it exists as a directory (from failed previous run)
                    if [ -d "${keystore_dir}/aggregator.keystore" ]; then
                        rm -rf "${keystore_dir}/aggregator.keystore"
                    fi
                    cp "${aggregator_keystore_file}" "${keystore_dir}/aggregator.keystore"
                    echo "✅ Copied aggregator keystore"
                fi
            fi

            local claimsponsor_keystore_artifact="claimsponsor-keystore${artifact_base}"
            local claimsponsor_keystore_dest="${TEMP_DIR}/${claimsponsor_keystore_artifact}"
            if download_artifact "${claimsponsor_keystore_artifact}" "${claimsponsor_keystore_dest}" 2>/dev/null; then
                local claimsponsor_keystore_file
                claimsponsor_keystore_file=$(find "${claimsponsor_keystore_dest}" -name "*.keystore" -type f | head -1 || echo "")
                if [ -n "${claimsponsor_keystore_file}" ]; then
                    # Remove if it exists as a directory (from failed previous run)
                    if [ -d "${keystore_dir}/claimsponsor.keystore" ]; then
                        rm -rf "${keystore_dir}/claimsponsor.keystore"
                    fi
                    cp "${claimsponsor_keystore_file}" "${keystore_dir}/claimsponsor.keystore"
                    echo "✅ Copied claimsponsor keystore"
                fi
            fi

            # Create aggoracle keystore from aggregator keystore (they use the same key)
            # AggOracle component needs this keystore but Kurtosis doesn't create a separate one
            if [ -f "${keystore_dir}/aggregator.keystore" ]; then
                cp "${keystore_dir}/aggregator.keystore" "${keystore_dir}/aggoracle.keystore"
                echo "✅ Created aggoracle keystore from aggregator keystore"
            fi

            # Update keystore mapping
            if command -v jq &> /dev/null; then
                keystore_mapping=$(echo "${keystore_mapping}" | jq --arg network_id "${network_id}" --arg keystore_dir "${keystore_dir}" \
                    '. + {($network_id): $keystore_dir}' 2>/dev/null || echo "${keystore_mapping}")
            fi
            
            # Allocate ports for this network
            if command -v jq &> /dev/null; then
                local network_port_mapping
                network_port_mapping=$(cat <<EOF
{
    "l2_rpc_http": $((base_cdk_erigon_rpc + network_id - 1)),
    "aggkit_aggregator": $((base_aggkit_aggregator + network_id - 1))
}
EOF
)
                port_mapping=$(echo "${port_mapping}" | jq --arg network_id "${network_id}" --argjson ports "${network_port_mapping}" \
                    '. + {($network_id): $ports}' 2>/dev/null || echo "${port_mapping}")
            fi
            
            # Add to processed networks with additional metadata for agglayer config
            if command -v jq &> /dev/null; then
                local network_info
                network_info=$(echo "${networks_data}" | jq --arg http_rpc_port "${http_rpc_port}" \
                    ".[${i}] + {http_rpc_port: (\$http_rpc_port | tonumber)}" 2>/dev/null || echo "{}")
                processed_networks=$(echo "${processed_networks}" | jq --argjson network "${network_info}" '. + [$network]' 2>/dev/null || echo "${processed_networks}")
            fi
            
            echo ""
        done
    else
        echo "Warning: jq not available or no networks data, skipping network processing"
        echo "You may need to manually process configs or provide networks JSON"
    fi
    
    # Process agglayer config
    log_section "Processing agglayer config"
    
    local agglayer_config_dest="${TEMP_DIR}/agglayer-config"
    if download_artifact "agglayer-config" "${agglayer_config_dest}" 2>/dev/null; then
        local agglayer_config_file
        agglayer_config_file=$(find "${agglayer_config_dest}" -name "config.toml" -type f | head -1 || echo "")
        
        if [ -n "${agglayer_config_file}" ]; then
            local agglayer_output_dir="${OUTPUT_DIR}/configs/agglayer"
            mkdir -p "${agglayer_output_dir}"
            
            local agglayer_content
            agglayer_content=$(read_toml_file "${agglayer_config_file}")
            
            # Update full-node-rpcs section
            agglayer_content=$(update_agglayer_full_node_rpcs "${agglayer_content}" "${processed_networks}")
            
            # Update proof-signers section
            agglayer_content=$(update_agglayer_proof_signers "${agglayer_content}" "${processed_networks}")
            
            # Convert service URLs in agglayer config
            # Replace L1 RPC URL to use docker-compose service name
            agglayer_content=$(echo "${agglayer_content}" | sed "s|node-url = \"http://[^\"]*\"|node-url = \"http://l1-geth:8545\"|g")
            agglayer_content=$(echo "${agglayer_content}" | sed "s|ws-node-url = \"ws://[^\"]*\"|ws-node-url = \"ws://l1-geth:8546\"|g")
            agglayer_content=$(echo "${agglayer_content}" | sed "s|l1_rpc_url = \"http://[^\"]*\"|l1_rpc_url = \"http://l1-geth:8545\"|g")

            write_toml_file "${agglayer_output_dir}/config.toml" "${agglayer_content}"
            
            # Validate agglayer config
            if validate_config_file "${agglayer_output_dir}/config.toml" "toml"; then
                if validate_toml "${agglayer_output_dir}/config.toml"; then
                    log_success "Agglayer config processed and validated successfully"
                else
                    log_warn "Agglayer config validation warning (continuing anyway)"
                fi
            else
                log_warn "Agglayer config syntax validation warning (continuing anyway)"
            fi
        else
            echo "Warning: Agglayer config file not found in artifact"
        fi
    else
        echo "Warning: Agglayer config artifact not found"
    fi
    
    echo ""
    
    # Create port mapping
    echo "Creating port mapping..."
    local port_mapping_file="${OUTPUT_DIR}/port-mapping.json"
    write_json_file "${port_mapping_file}" "${port_mapping}"
    echo "✅ Port mapping created: ${port_mapping_file}"
    
    # Create keystore mapping
    echo "Creating keystore mapping..."
    local keystore_mapping_file="${OUTPUT_DIR}/keystore-mapping.json"
    write_json_file "${keystore_mapping_file}" "${keystore_mapping}"
    echo "✅ Keystore mapping created: ${keystore_mapping_file}"
    
    # Create processing manifest
    echo "Creating processing manifest..."
    local manifest_file="${OUTPUT_DIR}/config-processing-manifest.json"
    local manifest_json
    manifest_json=$(cat <<EOF
{
    "processing_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "enclave_name": "${ENCLAVE_NAME}",
    "output_directory": "${OUTPUT_DIR}",
    "processed_networks": ${processed_networks},
    "port_mapping": ${port_mapping},
    "keystore_mapping": ${keystore_mapping}
}
EOF
)
    write_json_file "${manifest_file}" "${manifest_json}"
    echo "✅ Processing manifest created: ${manifest_file}"
    
    log_section "Summary"
    log_info "Processed configs: ${OUTPUT_DIR}/configs/"
    log_info "Keystores: ${OUTPUT_DIR}/keystores/"
    log_info "Mappings: ${OUTPUT_DIR}/*.json"
    
    log_success "Config Processing Complete"
}

# Run main function
main "$@"
