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

# Source helper functions
source "${UTILS_DIR}/config-processor.sh"

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

# Process CDK-Node config
# Usage: process_cdk_node_config <input_file> <output_file> <deployment_suffix> <network_id> <l2_rpc_name> <http_rpc_port>
process_cdk_node_config() {
    local input_file="$1"
    local output_file="$2"
    local deployment_suffix="$3"
    local network_id="$4"
    local l2_rpc_name="$5"
    local http_rpc_port="${6:-8123}"
    
    if [ ! -f "${input_file}" ]; then
        echo "Warning: CDK-Node config not found: ${input_file}"
        return 0
    fi
    
    echo "Processing CDK-Node config for network ${network_id}..."
    
    local config_content
    config_content=$(read_toml_file "${input_file}")
    
    # Convert service URLs
    config_content=$(replace_urls_in_config "${config_content}" "${deployment_suffix}" "${network_id}")
    
    # Replace L2 RPC URL
    config_content=$(echo "${config_content}" | sed "s|L2URL=\"http://[^\"]*\"|L2URL=\"http://${l2_rpc_name}-${network_id}:${http_rpc_port}\"|g")
    config_content=$(echo "${config_content}" | sed "s|l2_rpc_url = \"http://[^\"]*\"|l2_rpc_url = \"http://${l2_rpc_name}-${network_id}:${http_rpc_port}\"|g")
    
    # Replace agglayer endpoint (if present)
    config_content=$(echo "${config_content}" | sed "s|agglayer_endpoint = \"http://[^\"]*\"|agglayer_endpoint = \"http://agglayer:8080\"|g")
    
    write_toml_file "${output_file}" "${config_content}"
    
    # Validate
    if validate_toml "${output_file}"; then
        echo "✅ CDK-Node config processed successfully"
    else
        echo "⚠️  CDK-Node config validation warning (continuing anyway)"
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
    
    # Replace L2 URL
    config_content=$(echo "${config_content}" | sed "s|L2URL=\"http://[^\"]*\"|L2URL=\"http://${l2_rpc_name}-${network_id}:${http_rpc_port}\"|g")
    
    # Replace agglayer URL
    config_content=$(echo "${config_content}" | sed "s|AggLayerURL=\"http://[^\"]*\"|AggLayerURL=\"http://agglayer:8080\"|g")
    
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
        write_toml_file "${output_file}" "${config_content}"
    fi
}

# Main processing function
main() {
    echo "=========================================="
    echo "Config Processing for Snapshot"
    echo "=========================================="
    echo ""
    
    # Parse arguments
    parse_args "$@"
    
    # Create output directories
    mkdir -p "${OUTPUT_DIR}/configs"
    mkdir -p "${OUTPUT_DIR}/keystores"
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT
    
    echo "Enclave: ${ENCLAVE_NAME}"
    echo "Output directory: ${OUTPUT_DIR}"
    echo "Temporary directory: ${TEMP_DIR}"
    echo ""
    
    # Try to get artifact list from Kurtosis if manifest not provided
    if [ -z "${ARTIFACT_MANIFEST}" ]; then
        echo "Attempting to list artifacts from Kurtosis enclave..."
        # Note: Kurtosis may not have a direct command to list artifacts
        # We'll need to try downloading known artifact names
        ARTIFACT_MANIFEST="${TEMP_DIR}/artifact-manifest.json"
        echo "{}" > "${ARTIFACT_MANIFEST}"
    fi
    
    # Load networks configuration
    local networks_data="[]"
    if [ -n "${NETWORKS_JSON}" ] && [ -f "${NETWORKS_JSON}" ]; then
        networks_data=$(cat "${NETWORKS_JSON}")
    else
        echo "Warning: Networks JSON not provided, will try to infer from artifacts"
    fi
    
    # Extract network information from networks_data
    local network_count=0
    if command -v jq &> /dev/null && [ "${networks_data}" != "[]" ]; then
        network_count=$(echo "${networks_data}" | jq 'length' 2>/dev/null || echo "0")
    fi
    
    echo "Processing ${network_count} networks..."
    echo ""
    
    # Process each network
    local processed_networks="[]"
    local port_mapping="{}"
    local keystore_mapping="{}"
    
    if [ "${network_count}" -gt 0 ] && command -v jq &> /dev/null; then
        for i in $(seq 0 $((network_count - 1))); do
            local network_id
            network_id=$(echo "${networks_data}" | jq -r ".[${i}].network_id" 2>/dev/null || echo "")
            local deployment_suffix
            deployment_suffix=$(echo "${networks_data}" | jq -r ".[${i}].deployment_suffix // \"\"" 2>/dev/null || echo "")
            local sequencer_type
            sequencer_type=$(echo "${networks_data}" | jq -r ".[${i}].sequencer_type" 2>/dev/null || echo "")
            local l2_rpc_name
            l2_rpc_name=$(echo "${networks_data}" | jq -r ".[${i}].l2_rpc_name // \"cdk-erigon-rpc\"" 2>/dev/null || echo "cdk-erigon-rpc")
            local http_rpc_port
            http_rpc_port=$(echo "${networks_data}" | jq -r ".[${i}].http_rpc_port // 8123" 2>/dev/null || echo "8123")
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
            
            # Download CDK-Node config
            local cdk_node_artifact="cdk-node-config${artifact_base}"
            local cdk_node_dest="${TEMP_DIR}/${cdk_node_artifact}"
            if download_artifact "${cdk_node_artifact}" "${cdk_node_dest}" 2>/dev/null; then
                # Find the actual config file
                local cdk_node_config_file
                cdk_node_config_file=$(find "${cdk_node_dest}" -name "config.toml" -type f | head -1 || echo "")
                if [ -n "${cdk_node_config_file}" ]; then
                    process_cdk_node_config "${cdk_node_config_file}" "${network_output_dir}/cdk-node-config.toml" "${deployment_suffix}" "${network_id}" "${l2_rpc_name}" "${http_rpc_port}"
                fi
            fi
            
            # Download AggKit config
            local aggkit_artifact="aggkit-cdk-config${artifact_base}"
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
                        cp "${chain_allocs_file}" "${network_output_dir}/chain-allocs.json"
                        echo "✅ Copied chain-allocs.json"
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
                    cp "${aggregator_keystore_file}" "${keystore_dir}/aggregator.keystore"
                    echo "✅ Copied aggregator keystore"
                fi
            fi
            
            # Update keystore mapping
            if command -v jq &> /dev/null; then
                keystore_mapping=$(echo "${keystore_mapping}" | jq --arg network_id "${network_id}" --arg keystore_dir "${keystore_dir}" \
                    '. + {($network_id): $keystore_dir}' 2>/dev/null || echo "${keystore_mapping}")
            fi
            
            # Add to processed networks
            if command -v jq &> /dev/null; then
                local network_info
                network_info=$(echo "${networks_data}" | jq ".[${i}]" 2>/dev/null || echo "{}")
                processed_networks=$(echo "${processed_networks}" | jq --argjson network "${network_info}" '. + [$network]' 2>/dev/null || echo "${processed_networks}")
            fi
            
            echo ""
        done
    else
        echo "Warning: jq not available or no networks data, skipping network processing"
        echo "You may need to manually process configs or provide networks JSON"
    fi
    
    # Process agglayer config
    echo "----------------------------------------"
    echo "Processing agglayer config"
    echo "----------------------------------------"
    
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
            agglayer_content=$(echo "${agglayer_content}" | sed "s|l1_rpc_url = \"http://[^\"]*\"|l1_rpc_url = \"http://l1-geth:8545\"|g")
            
            write_toml_file "${agglayer_output_dir}/config.toml" "${agglayer_content}"
            
            if validate_toml "${agglayer_output_dir}/config.toml"; then
                echo "✅ Agglayer config processed successfully"
            else
                echo "⚠️  Agglayer config validation warning (continuing anyway)"
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
    
    echo ""
    echo "=========================================="
    echo "Config Processing Complete"
    echo "=========================================="
    echo "Processed configs: ${OUTPUT_DIR}/configs/"
    echo "Keystores: ${OUTPUT_DIR}/keystores/"
    echo "Mappings: ${OUTPUT_DIR}/*.json"
    echo ""
}

# Run main function
main "$@"
