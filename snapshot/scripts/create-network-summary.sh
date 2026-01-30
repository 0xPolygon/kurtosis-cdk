#!/bin/bash
# Create comprehensive network summary.json file
#
# This script creates a summary.json file that contains all the critical
# information about the L1 and L2 networks, including:
# - Contract addresses
# - Account addresses and private keys
# - RPC URLs (docker-internal and localhost)
# - Chain IDs and network configuration

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"

# Default values
OUTPUT_DIR=""
NETWORKS_JSON=""

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Create comprehensive network summary.json file for snapshot.

Options:
    --output-dir DIR          Output directory containing snapshot (required)
    --networks-json FILE      Networks configuration JSON (optional)
    -h, --help                Show this help message

Example:
    $0 --output-dir ./snapshot-output --networks-json ./networks.json
EOF
    exit 1
}

# Parse arguments
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

log_section "Creating Network Summary"

# Extract L1 information
log_info "Extracting L1 information..."

# Get L1 chain ID from genesis
L1_GENESIS="${OUTPUT_DIR}/l1-config/genesis.json"
L1_CHAIN_ID="271828"
if [ -f "${L1_GENESIS}" ]; then
    L1_CHAIN_ID=$(jq -r '.config.chainId // 271828' "${L1_GENESIS}" 2>/dev/null || echo "271828")
fi

# L1 prefunded account (from ethereum-package default mnemonic)
L1_PREFUNDED_ADDRESS="0x8943545177806ED17B9F23F0a21ee5948eCaa776"
L1_PREFUNDED_PRIVATE_KEY="0xbcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31"

# Try to find L1 contract addresses from first network's aggkit config
L1_CONTRACTS="{}"
# Find a network config directory (numeric directory name, not 'agglayer')
FIRST_NETWORK_CONFIG=$(find "${OUTPUT_DIR}/configs" -mindepth 1 -maxdepth 1 -type d -regex '.*/[0-9]+$' | head -1)
if [ -n "${FIRST_NETWORK_CONFIG}" ] && [ -f "${FIRST_NETWORK_CONFIG}/aggkit-config.toml" ]; then
    log_info "Reading L1 contract addresses from aggkit config..."

    # Extract contract addresses from TOML
    AGGKIT_CONFIG="${FIRST_NETWORK_CONFIG}/aggkit-config.toml"

    # Extract key contract addresses
    ROLLUP_MANAGER=$(grep "polygonRollupManagerAddress" "${AGGKIT_CONFIG}" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1 || echo "")
    GER_L1=$(grep "polygonZkEVMGlobalExitRootAddress" "${AGGKIT_CONFIG}" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1 || echo "")
    POL_TOKEN=$(grep "polTokenAddress" "${AGGKIT_CONFIG}" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1 || echo "")

    # Try to find bridge address from rollup.json or aggkit config
    BRIDGE_L1=""
    if [ -f "${FIRST_NETWORK_CONFIG}/rollup.json" ]; then
        DEPOSIT_CONTRACT=$(jq -r '.deposit_contract_address // ""' "${FIRST_NETWORK_CONFIG}/rollup.json" 2>/dev/null || echo "")
        SYSTEM_CONFIG=$(jq -r '.l1_system_config_address // ""' "${FIRST_NETWORK_CONFIG}/rollup.json" 2>/dev/null || echo "")
        PROTOCOL_VERSIONS=$(jq -r '.protocol_versions_address // ""' "${FIRST_NETWORK_CONFIG}/rollup.json" 2>/dev/null || echo "")
        BATCH_INBOX=$(jq -r '.batch_inbox_address // ""' "${FIRST_NETWORK_CONFIG}/rollup.json" 2>/dev/null || echo "")
    fi

    # Build L1 contracts JSON
    L1_CONTRACTS=$(jq -n \
        --arg rollup_manager "${ROLLUP_MANAGER}" \
        --arg ger "${GER_L1}" \
        --arg pol_token "${POL_TOKEN}" \
        --arg deposit_contract "${DEPOSIT_CONTRACT:-}" \
        --arg system_config "${SYSTEM_CONFIG:-}" \
        --arg protocol_versions "${PROTOCOL_VERSIONS:-}" \
        --arg batch_inbox "${BATCH_INBOX:-}" \
        '{
            rollup_manager: $rollup_manager,
            global_exit_root: $ger,
            pol_token: $pol_token
        } + (if $deposit_contract != "" then {deposit_contract: $deposit_contract} else {} end)
          + (if $system_config != "" then {system_config: $system_config} else {} end)
          + (if $protocol_versions != "" then {protocol_versions: $protocol_versions} else {} end)
          + (if $batch_inbox != "" then {batch_inbox: $batch_inbox} else {} end)
    ')
fi

# Build L1 summary
L1_SUMMARY=$(jq -n \
    --arg chain_id "${L1_CHAIN_ID}" \
    --argjson contracts "${L1_CONTRACTS}" \
    --arg prefunded_addr "${L1_PREFUNDED_ADDRESS}" \
    --arg prefunded_key "${L1_PREFUNDED_PRIVATE_KEY}" \
    '{
        chain_id: ($chain_id | tonumber),
        contracts: $contracts,
        accounts: {
            prefunded: [
                {
                    address: $prefunded_addr,
                    private_key: $prefunded_key,
                    role: "Prefunded account from default mnemonic",
                    balance: "1000000 ETH (approximate)"
                }
            ]
        },
        rpc: {
            docker_url: "http://l1-geth:8545",
            localhost_url: "http://localhost:8545",
            ws_docker_url: "ws://l1-geth:8546",
            ws_localhost_url: "ws://localhost:8546"
        }
    }
')

log_success "L1 information extracted"

# Extract L2 networks information
log_info "Extracting L2 networks information..."

# Try to load networks from kurtosis-args.json or networks-json
NETWORKS_DATA="[]"
if [ -f "${OUTPUT_DIR}/kurtosis-args.json" ]; then
    NETWORKS_DATA=$(jq -c '.args.snapshot_networks // []' "${OUTPUT_DIR}/kurtosis-args.json" 2>/dev/null || echo "[]")
elif [ -n "${NETWORKS_JSON}" ] && [ -f "${NETWORKS_JSON}" ]; then
    NETWORKS_DATA=$(jq -c '.networks // .' "${NETWORKS_JSON}" 2>/dev/null || echo "[]")
fi

NETWORK_COUNT=$(echo "${NETWORKS_DATA}" | jq 'length' 2>/dev/null || echo "0")

log_info "Found ${NETWORK_COUNT} network(s)"

# Build L2 networks array
L2_NETWORKS="[]"

if [ "${NETWORK_COUNT}" -gt 0 ]; then
    for i in $(seq 0 $((NETWORK_COUNT - 1))); do
        # Extract network info from networks data
        NETWORK_ID=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].network_id" 2>/dev/null || echo "")
        SEQUENCER_TYPE=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].sequencer_type" 2>/dev/null || echo "")
        CONSENSUS_TYPE=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].consensus_type" 2>/dev/null || echo "")
        L2_CHAIN_ID=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_chain_id" 2>/dev/null || echo "")

        # Extract account addresses and keys
        SEQUENCER_ADDR=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_sequencer_address // \"\"" 2>/dev/null || echo "")
        SEQUENCER_KEY=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_sequencer_private_key // \"\"" 2>/dev/null || echo "")
        AGGREGATOR_ADDR=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_aggregator_address // \"\"" 2>/dev/null || echo "")
        AGGREGATOR_KEY=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_aggregator_private_key // \"\"" 2>/dev/null || echo "")
        ADMIN_ADDR=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_admin_address // \"\"" 2>/dev/null || echo "")
        ADMIN_KEY=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_admin_private_key // \"\"" 2>/dev/null || echo "")
        DAC_ADDR=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_dac_address // \"\"" 2>/dev/null || echo "")
        DAC_KEY=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_dac_private_key // \"\"" 2>/dev/null || echo "")
        CLAIMSPONSOR_ADDR=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_claimsponsor_address // \"\"" 2>/dev/null || echo "")
        CLAIMSPONSOR_KEY=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_claimsponsor_private_key // \"\"" 2>/dev/null || echo "")
        SOVEREIGN_ADMIN_ADDR=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_sovereignadmin_address // \"\"" 2>/dev/null || echo "")
        SOVEREIGN_ADMIN_KEY=$(echo "${NETWORKS_DATA}" | jq -r ".[${i}].l2_sovereignadmin_private_key // \"\"" 2>/dev/null || echo "")

        if [ -z "${NETWORK_ID}" ] || [ "${NETWORK_ID}" = "null" ]; then
            log_warn "Skipping network ${i} (missing network_id)"
            continue
        fi

        log_info "Processing network ${NETWORK_ID}..."

        # Extract L2 contract addresses
        L2_CONTRACTS="{}"
        NETWORK_CONFIG_DIR="${OUTPUT_DIR}/configs/${NETWORK_ID}"

        if [ -f "${NETWORK_CONFIG_DIR}/l2-contracts.json" ]; then
            L2_GER=$(jq -r '.l2_ger_address // ""' "${NETWORK_CONFIG_DIR}/l2-contracts.json" 2>/dev/null || echo "")
            L2_BRIDGE=$(jq -r '.l2_bridge_address // ""' "${NETWORK_CONFIG_DIR}/l2-contracts.json" 2>/dev/null || echo "")

            L2_CONTRACTS=$(jq -n \
                --arg l2_ger "${L2_GER}" \
                --arg l2_bridge "${L2_BRIDGE}" \
                '{
                    l2_global_exit_root: $l2_ger,
                    l2_bridge: $l2_bridge
                }
            ')
        fi

        # Extract L1 rollup contract address for this network
        ROLLUP_CONTRACT=""
        if [ -f "${NETWORK_CONFIG_DIR}/aggkit-config.toml" ]; then
            ROLLUP_CONTRACT=$(grep "polygonZkEVMAddress" "${NETWORK_CONFIG_DIR}/aggkit-config.toml" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1 || echo "")
        fi

        if [ -n "${ROLLUP_CONTRACT}" ]; then
            L2_CONTRACTS=$(echo "${L2_CONTRACTS}" | jq \
                --arg rollup "${ROLLUP_CONTRACT}" \
                '. + {l1_rollup_contract: $rollup}'
            )
        fi

        # Determine RPC service name based on sequencer type
        RPC_SERVICE="op-geth"
        RPC_PORT="8545"
        if [ "${SEQUENCER_TYPE}" = "cdk-erigon" ]; then
            RPC_SERVICE="cdk-erigon-rpc"
            RPC_PORT="8123"
        fi

        # Calculate localhost port (8123 base for CDK-Erigon, 8545 base for OP-Geth + network_id - 1)
        LOCALHOST_PORT=$((RPC_PORT + NETWORK_ID - 1))

        # Build accounts array
        ACCOUNTS="[]"

        # Add sequencer if available
        if [ -n "${SEQUENCER_ADDR}" ] && [ "${SEQUENCER_ADDR}" != "null" ]; then
            ACCOUNTS=$(echo "${ACCOUNTS}" | jq \
                --arg addr "${SEQUENCER_ADDR}" \
                --arg key "${SEQUENCER_KEY}" \
                '. + [{address: $addr, private_key: $key, role: "sequencer"}]'
            )
        fi

        # Add aggregator if available
        if [ -n "${AGGREGATOR_ADDR}" ] && [ "${AGGREGATOR_ADDR}" != "null" ]; then
            ACCOUNTS=$(echo "${ACCOUNTS}" | jq \
                --arg addr "${AGGREGATOR_ADDR}" \
                --arg key "${AGGREGATOR_KEY}" \
                '. + [{address: $addr, private_key: $key, role: "aggregator"}]'
            )
        fi

        # Add admin if available
        if [ -n "${ADMIN_ADDR}" ] && [ "${ADMIN_ADDR}" != "null" ]; then
            ACCOUNTS=$(echo "${ACCOUNTS}" | jq \
                --arg addr "${ADMIN_ADDR}" \
                --arg key "${ADMIN_KEY}" \
                '. + [{address: $addr, private_key: $key, role: "admin"}]'
            )
        fi

        # Add DAC if available
        if [ -n "${DAC_ADDR}" ] && [ "${DAC_ADDR}" != "null" ]; then
            ACCOUNTS=$(echo "${ACCOUNTS}" | jq \
                --arg addr "${DAC_ADDR}" \
                --arg key "${DAC_KEY}" \
                '. + [{address: $addr, private_key: $key, role: "data_availability_committee"}]'
            )
        fi

        # Add claim sponsor if available
        if [ -n "${CLAIMSPONSOR_ADDR}" ] && [ "${CLAIMSPONSOR_ADDR}" != "null" ]; then
            ACCOUNTS=$(echo "${ACCOUNTS}" | jq \
                --arg addr "${CLAIMSPONSOR_ADDR}" \
                --arg key "${CLAIMSPONSOR_KEY}" \
                '. + [{address: $addr, private_key: $key, role: "claim_sponsor"}]'
            )
        fi

        # Add sovereign admin if available
        if [ -n "${SOVEREIGN_ADMIN_ADDR}" ] && [ "${SOVEREIGN_ADMIN_ADDR}" != "null" ]; then
            ACCOUNTS=$(echo "${ACCOUNTS}" | jq \
                --arg addr "${SOVEREIGN_ADMIN_ADDR}" \
                --arg key "${SOVEREIGN_ADMIN_KEY}" \
                '. + [{address: $addr, private_key: $key, role: "sovereign_admin"}]'
            )
        fi

        # Add L1 prefunded account (has funds on both L1 and L2)
        ACCOUNTS=$(echo "${ACCOUNTS}" | jq \
            --arg addr "${L1_PREFUNDED_ADDRESS}" \
            --arg key "${L1_PREFUNDED_PRIVATE_KEY}" \
            '. + [{address: $addr, private_key: $key, role: "prefunded", balance: "100 ETH (approximate)"}]'
        )

        # Build network summary
        NETWORK_SUMMARY=$(jq -n \
            --arg network_id "${NETWORK_ID}" \
            --arg sequencer_type "${SEQUENCER_TYPE}" \
            --arg consensus_type "${CONSENSUS_TYPE}" \
            --arg chain_id "${L2_CHAIN_ID}" \
            --argjson contracts "${L2_CONTRACTS}" \
            --argjson accounts "${ACCOUNTS}" \
            --arg rpc_service "${RPC_SERVICE}" \
            --arg localhost_port "${LOCALHOST_PORT}" \
            '{
                network_id: ($network_id | tonumber),
                chain_id: ($chain_id | tonumber),
                sequencer_type: $sequencer_type,
                consensus_type: $consensus_type,
                contracts: $contracts,
                accounts: $accounts,
                rpc: {
                    docker_url: ("http://" + $rpc_service + "-" + $network_id + ":8545"),
                    localhost_url: ("http://localhost:" + $localhost_port)
                }
            }
        ')

        # Add to L2 networks array
        L2_NETWORKS=$(echo "${L2_NETWORKS}" | jq --argjson network "${NETWORK_SUMMARY}" '. + [$network]')

        log_success "Network ${NETWORK_ID} processed"
    done
fi

log_success "L2 networks information extracted"

# Create final summary
log_info "Creating summary.json..."

SUMMARY_FILE="${OUTPUT_DIR}/summary.json"

SUMMARY=$(jq -n \
    --argjson l1 "${L1_SUMMARY}" \
    --argjson l2_networks "${L2_NETWORKS}" \
    --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
        created_at: $created,
        l1: $l1,
        l2_networks: $l2_networks
    }
')

echo "${SUMMARY}" | jq '.' > "${SUMMARY_FILE}"

log_success "Summary created: ${SUMMARY_FILE}"

# Print summary info
log_info ""
log_info "=========================================="
log_info "Network Summary"
log_info "=========================================="
log_info "L1 Chain ID: ${L1_CHAIN_ID}"
log_info "L2 Networks: ${NETWORK_COUNT}"
log_info "Summary file: ${SUMMARY_FILE}"
log_info ""

exit 0
