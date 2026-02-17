#!/usr/bin/env bash
#
# Generate Summary JSON Script
# Creates summary.json with contract addresses, service URLs, and accounts
#
# Usage: generate-summary.sh <DISCOVERY_JSON> <OUTPUT_DIR>
#

set -euo pipefail

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <DISCOVERY_JSON> <OUTPUT_DIR>" >&2
    exit 1
fi

DISCOVERY_JSON="$1"
OUTPUT_DIR="$2"

# Create temp directory for intermediate files to avoid "Argument list too long" errors
TEMP_DIR="${OUTPUT_DIR}/.tmp_summary_$$"
mkdir -p "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Check dependencies
for cmd in jq curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Required command '$cmd' not found" >&2
        exit 1
    fi
done

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting summary.json generation"

# Read discovery info
if [ ! -f "$DISCOVERY_JSON" ]; then
    log "ERROR: Discovery file not found: $DISCOVERY_JSON"
    exit 1
fi

ENCLAVE_NAME=$(jq -r '.enclave_name' "$DISCOVERY_JSON")
SNAPSHOT_ID=$(basename "$OUTPUT_DIR")

# Get checkpoint info
CHECKPOINT_FILE="$OUTPUT_DIR/metadata/checkpoint.json"
if [ -f "$CHECKPOINT_FILE" ]; then
    L1_BLOCK=$(jq -r '.l1_state.block_number' "$CHECKPOINT_FILE")
    L1_HASH=$(jq -r '.l1_state.block_hash' "$CHECKPOINT_FILE")
    GENESIS_HASH=$(jq -r '.l1_state.genesis_hash' "$CHECKPOINT_FILE")
else
    L1_BLOCK="unknown"
    L1_HASH="unknown"
    GENESIS_HASH="unknown"
fi

# Get L1 chain ID from genesis
L1_CHAIN_ID="271828"  # default
GENESIS_FILE="$OUTPUT_DIR/artifacts/genesis.json"
if [ -f "$GENESIS_FILE" ]; then
    L1_CHAIN_ID=$(jq -r '.config.chainId // "271828"' "$GENESIS_FILE")
fi

# Check if agglayer exists
AGGLAYER_FOUND=$(jq -r '.agglayer.found // false' "$DISCOVERY_JSON")

# Check if L2 chains exist
L2_CHAINS_COUNT=$(jq -r '.l2_chains | length // 0' "$DISCOVERY_JSON" 2>/dev/null || echo "0")

# ============================================================================
# Helper Functions
# ============================================================================

# Default mnemonics used for test accounts
DEFAULT_L1_MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
DEFAULT_L2_MNEMONIC="test test test test test test test test test test test junk"

# Build a map of address -> private key from mnemonic
build_private_key_map() {
    local mnemonic="$1"
    local count="${2:-100}"  # Generate first 100 accounts

    echo "{}" > "$TEMP_DIR/pk_map.json"

    for i in $(seq 0 $((count - 1))); do
        # Derive address and private key
        local addr
        addr=$(cast wallet address --mnemonic "$mnemonic" --mnemonic-index "$i" 2>/dev/null || echo "")
        local pk
        pk=$(cast wallet private-key --mnemonic "$mnemonic" --mnemonic-index "$i" 2>/dev/null || echo "")

        if [ -n "$addr" ] && [ -n "$pk" ]; then
            # Add to map (convert address to lowercase for matching)
            jq --arg addr "${addr,,}" --arg pk "$pk" '. + {($addr): $pk}' "$TEMP_DIR/pk_map.json" > "$TEMP_DIR/pk_map_tmp.json"
            mv "$TEMP_DIR/pk_map_tmp.json" "$TEMP_DIR/pk_map.json"
        fi
    done
}

# Extract accounts from genesis file (only meaningful accounts with balance > 1)
extract_genesis_accounts() {
    local genesis_file="$1"
    local description_prefix="$2"
    local exclude_op_contracts="${3:-false}"
    local pk_map_file="$TEMP_DIR/pk_map.json"

    if [ ! -f "$genesis_file" ]; then
        echo "[]"
        return
    fi

    # Load private key map if available
    local pk_map="{}"
    if [ -f "$pk_map_file" ]; then
        pk_map=$(cat "$pk_map_file")
    fi

    # Extract accounts with meaningful balance, excluding precompiles and optionally OP contracts
    if [ "$exclude_op_contracts" = "true" ]; then
        jq --arg desc "$description_prefix" --argjson pk_map "$pk_map" '
            .alloc // {} | to_entries |
            map(select(
                # Exclude precompile addresses (0x0000...0000 through 0x0000...00ff)
                (.key | test("^0x000000000000000000000000000000000000") | not) and
                # Exclude OP predeploy contracts (0x4200...)
                (.key | test("^0x4200|^0420") | not) and
                # Only include accounts with balance > 1
                ((.value.balance | if type == "string" then
                    if startswith("0x") then
                        # Hex balance: exclude 0x0 and 0x1
                        . != "0x0" and . != "0x1"
                    else
                        # Decimal balance: exclude 0 and 1
                        (. | tonumber) > 1
                    end
                else false end))
            )) |
            map({
                address: (if .key | startswith("0x") then .key else ("0x" + .key) end),
                balance: .value.balance,
                private_key: (
                    .value.privateKey //
                    $pk_map[(if .key | startswith("0x") then .key else ("0x" + .key) end) | ascii_downcase] //
                    null
                ),
                description: ($desc + " pre-funded account")
            })
        ' "$genesis_file" 2>/dev/null || echo "[]"
    else
        jq --arg desc "$description_prefix" --argjson pk_map "$pk_map" '
            .alloc // {} | to_entries |
            map(select(
                # Exclude precompile addresses (0x0000...0000 through 0x0000...00ff)
                (.key | test("^0x000000000000000000000000000000000000") | not) and
                # Only include accounts with balance > 1
                ((.value.balance | if type == "string" then
                    if startswith("0x") then
                        # Hex balance: exclude 0x0 and 0x1
                        . != "0x0" and . != "0x1"
                    else
                        # Decimal balance: exclude 0 and 1
                        (. | tonumber) > 1
                    end
                else false end))
            )) |
            map({
                address: (if .key | startswith("0x") then .key else ("0x" + .key) end),
                balance: .value.balance,
                private_key: (
                    .value.privateKey //
                    $pk_map[(if .key | startswith("0x") then .key else ("0x" + .key) end) | ascii_downcase] //
                    null
                ),
                description: ($desc + " pre-funded account")
            })
        ' "$genesis_file" 2>/dev/null || echo "[]"
    fi
}

# Extract address from keystore file
extract_keystore_address() {
    local keystore_file="$1"

    if [ ! -f "$keystore_file" ]; then
        echo ""
        return
    fi

    # Keystore files contain the address in the "address" field
    jq -r '.address // empty' "$keystore_file" 2>/dev/null || echo ""
}

# Extract private key from keystore file (if possible - usually encrypted)
extract_keystore_privkey() {
    local keystore_file="$1"

    # Note: Keystores are encrypted, so we can't extract the private key directly
    # Return empty string to indicate it's encrypted
    echo ""
}

# Extract L1 contract addresses from agglayer and aggkit configs
extract_l1_contracts() {
    local output_dir="$1"
    local contracts="{}"

    # Extract from agglayer config if it exists
    local agglayer_config="$output_dir/config/agglayer/config.toml"
    if [ -f "$agglayer_config" ]; then
        local rollup_manager
        rollup_manager=$(grep -m1 "rollup-manager-contract" "$agglayer_config" | sed 's/.*= *"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
        local ger_contract
        ger_contract=$(grep -m1 "polygon-zkevm-global-exit-root-v2-contract" "$agglayer_config" | sed 's/.*= *"\([^"]*\)".*/\1/' 2>/dev/null || echo "")

        contracts=$(jq -n \
            --arg rollup_manager "$rollup_manager" \
            --arg ger "$ger_contract" \
            '{
                rollup_manager: (if $rollup_manager != "" then $rollup_manager else null end),
                global_exit_root_v2: (if $ger != "" then $ger else null end)
            }')
    fi

    # Also extract from first L2 aggkit config if available
    local aggkit_config="$output_dir/config/001/aggkit-config.toml"
    if [ -f "$aggkit_config" ]; then
        local bridge_addr
        bridge_addr=$(grep "^BridgeAddr" "$aggkit_config" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
        local pol_token
        pol_token=$(grep "polTokenAddress" "$aggkit_config" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
        local deposit_contract
        deposit_contract=$(jq -r '.config.depositContractAddress // empty' "$output_dir/artifacts/genesis.json" 2>/dev/null || echo "")

        contracts=$(echo "$contracts" | jq \
            --arg bridge "$bridge_addr" \
            --arg pol_token "$pol_token" \
            --arg deposit "$deposit_contract" \
            '. + {
                bridge: (if $bridge != "" then $bridge else null end),
                pol_token: (if $pol_token != "" then $pol_token else null end),
                deposit_contract: (if $deposit != "" then $deposit else null end)
            }')
    fi

    echo "$contracts"
}

# ============================================================================
# Build L1 Network Info
# ============================================================================

log "Building L1 network info..."

# Build private key maps from mnemonics (if cast is available)
if command -v cast &> /dev/null; then
    log "  Deriving private keys from L1 mnemonic..."
    build_private_key_map "$DEFAULT_L1_MNEMONIC" 50

    log "  Deriving private keys from L2 mnemonic..."
    # Append L2 private keys to the same map
    for i in $(seq 0 49); do
        addr=$(cast wallet address --mnemonic "$DEFAULT_L2_MNEMONIC" --mnemonic-index "$i" 2>/dev/null || echo "")
        pk=$(cast wallet private-key --mnemonic "$DEFAULT_L2_MNEMONIC" --mnemonic-index "$i" 2>/dev/null || echo "")

        if [ -n "$addr" ] && [ -n "$pk" ]; then
            jq --arg addr "${addr,,}" --arg pk "$pk" '. + {($addr): $pk}' "$TEMP_DIR/pk_map.json" > "$TEMP_DIR/pk_map_tmp.json"
            mv "$TEMP_DIR/pk_map_tmp.json" "$TEMP_DIR/pk_map.json"
        fi
    done
fi

# L1 contract addresses
L1_CONTRACTS=$(extract_l1_contracts "$OUTPUT_DIR")

# L1 service URLs
L1_SERVICES=$(cat <<EOF
{
    "geth": {
        "http_rpc": {
            "internal": "http://geth:8545",
            "external": "http://localhost:8545"
        },
        "ws_rpc": {
            "internal": "ws://geth:8546",
            "external": "ws://localhost:8546"
        },
        "engine_api": {
            "internal": "http://geth:8551",
            "external": "http://localhost:8551"
        },
        "metrics": {
            "internal": "http://geth:9001/debug/metrics/prometheus",
            "external": "http://localhost:9001/debug/metrics/prometheus"
        }
    },
    "beacon": {
        "http_api": {
            "internal": "http://beacon:4000",
            "external": "http://localhost:4000"
        },
        "metrics": {
            "internal": "http://beacon:5054/metrics",
            "external": "http://localhost:5054/metrics"
        }
    },
    "validator": {
        "metrics": {
            "internal": "http://validator:5064/metrics",
            "external": "http://localhost:5064/metrics"
        }
    }
}
EOF
)

# L1 accounts
L1_ACCOUNTS=$(extract_genesis_accounts "$GENESIS_FILE" "L1")

# Build L1 network object
# Use temp files to avoid "Argument list too long" errors
echo "$L1_CONTRACTS" > "$TEMP_DIR/l1_contracts.json"
echo "$L1_SERVICES" > "$TEMP_DIR/l1_services.json"
echo "$L1_ACCOUNTS" > "$TEMP_DIR/l1_accounts.json"

L1_NETWORK=$(jq -n \
    --slurpfile contracts "$TEMP_DIR/l1_contracts.json" \
    --slurpfile services "$TEMP_DIR/l1_services.json" \
    --slurpfile accounts "$TEMP_DIR/l1_accounts.json" \
    --arg chain_id "$L1_CHAIN_ID" \
    --arg block "$L1_BLOCK" \
    --arg hash "$L1_HASH" \
    --arg genesis_hash "$GENESIS_HASH" \
    '{
        chain_id: $chain_id,
        snapshot_block: {
            number: $block,
            hash: $hash
        },
        genesis_hash: $genesis_hash,
        contracts: $contracts[0],
        services: $services[0],
        accounts: $accounts[0]
    }')

# ============================================================================
# Build Agglayer Info (if present)
# ============================================================================

AGGLAYER_INFO="null"

if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "Building Agglayer info..."

    # Agglayer service URLs
    AGGLAYER_SERVICES=$(cat <<EOF
{
    "grpc_rpc": {
        "internal": "http://agglayer:4443",
        "external": "http://localhost:4443"
    },
    "read_rpc": {
        "internal": "http://agglayer:4444",
        "external": "http://localhost:4444"
    },
    "admin_api": {
        "internal": "http://agglayer:4446",
        "external": "http://localhost:4446"
    },
    "metrics": {
        "internal": "http://agglayer:9092/metrics",
        "external": "http://localhost:9092/metrics"
    }
}
EOF
)

    # Use temp files to avoid "Argument list too long" errors
    echo "$AGGLAYER_SERVICES" > "$TEMP_DIR/agglayer_services.json"

    AGGLAYER_INFO=$(jq -n \
        --slurpfile services "$TEMP_DIR/agglayer_services.json" \
        '{
            services: $services[0]
        }')
fi

# ============================================================================
# Build L2 Networks Info
# ============================================================================

L2_NETWORKS="{}"

if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    log "Building L2 networks info..."

    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        log "  Processing L2 network: $prefix"

        # Calculate port offsets
        PREFIX_NUM=$((10#$prefix))
        L2_HTTP_PORT=$((10000 + PREFIX_NUM * 1000 + 545))
        L2_WS_PORT=$((10000 + PREFIX_NUM * 1000 + 546))
        L2_ENGINE_PORT=$((10000 + PREFIX_NUM * 1000 + 551))
        L2_NODE_RPC_PORT=$((10000 + PREFIX_NUM * 1000 + 547))
        L2_NODE_METRICS_PORT=$((10000 + PREFIX_NUM * 1000 + 300))
        L2_AGGKIT_RPC_PORT=$((10000 + PREFIX_NUM * 1000 + 576))
        L2_AGGKIT_REST_PORT=$((10000 + PREFIX_NUM * 1000 + 577))

        # Get L2 chain ID
        ROLLUP_FILE="$OUTPUT_DIR/config/$prefix/rollup.json"
        L2_CHAIN_ID="unknown"
        if [ -f "$ROLLUP_FILE" ]; then
            L2_CHAIN_ID=$(jq -r '.l2_chain_id // .genesis.l2.chain_id // "unknown"' "$ROLLUP_FILE")
        fi

        # Extract contract addresses from aggkit config
        L2_CONTRACTS="{}"
        AGGKIT_CONFIG="$OUTPUT_DIR/config/$prefix/aggkit-config.toml"
        if [ -f "$AGGKIT_CONFIG" ]; then
            # Extract bridge addresses and other contracts (use head -1 to ensure single value)
            L1_BRIDGE=$(grep "^BridgeAddr" "$AGGKIT_CONFIG" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
            L2_BRIDGE=$(grep -A10 "^\[L2Config\]" "$AGGKIT_CONFIG" | grep "^BridgeAddr" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
            ROLLUP_MANAGER=$(grep "RollupManagerAddr" "$AGGKIT_CONFIG" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")
            GER_CONTRACT=$(grep -A10 "^\[L2Config\]" "$AGGKIT_CONFIG" | grep "^GlobalExitRootAddr" | head -1 | cut -d'"' -f2 2>/dev/null || echo "")

            L2_CONTRACTS=$(jq -n \
                --arg l1_bridge "$L1_BRIDGE" \
                --arg l2_bridge "$L2_BRIDGE" \
                --arg rollup_manager "$ROLLUP_MANAGER" \
                --arg ger "$GER_CONTRACT" \
                '{
                    l1_bridge: (if $l1_bridge != "" then $l1_bridge else null end),
                    l2_bridge: (if $l2_bridge != "" then $l2_bridge else null end),
                    rollup_manager: (if $rollup_manager != "" then $rollup_manager else null end),
                    global_exit_root: (if $ger != "" then $ger else null end)
                }')
        fi

        # L2 service URLs
        L2_SERVICES=$(jq -n \
            --arg prefix "$prefix" \
            --arg http_port "$L2_HTTP_PORT" \
            --arg ws_port "$L2_WS_PORT" \
            --arg engine_port "$L2_ENGINE_PORT" \
            --arg node_rpc_port "$L2_NODE_RPC_PORT" \
            --arg node_metrics_port "$L2_NODE_METRICS_PORT" \
            --arg aggkit_rpc_port "$L2_AGGKIT_RPC_PORT" \
            --arg aggkit_rest_port "$L2_AGGKIT_REST_PORT" \
            '{
                "op-geth": {
                    http_rpc: {
                        internal: ("http://op-geth-" + $prefix + ":8545"),
                        external: ("http://localhost:" + $http_port)
                    },
                    ws_rpc: {
                        internal: ("ws://op-geth-" + $prefix + ":8546"),
                        external: ("ws://localhost:" + $ws_port)
                    },
                    engine_api: {
                        internal: ("http://op-geth-" + $prefix + ":8551"),
                        external: ("http://localhost:" + $engine_port)
                    }
                },
                "op-node": {
                    rpc: {
                        internal: ("http://op-node-" + $prefix + ":8547"),
                        external: ("http://localhost:" + $node_rpc_port)
                    },
                    metrics: {
                        internal: ("http://op-node-" + $prefix + ":7300"),
                        external: ("http://localhost:" + $node_metrics_port)
                    }
                }
            }')

        # Add aggkit services if present
        if [ -f "$AGGKIT_CONFIG" ]; then
            L2_SERVICES=$(echo "$L2_SERVICES" | jq \
                --arg prefix "$prefix" \
                --arg rpc_port "$L2_AGGKIT_RPC_PORT" \
                --arg rest_port "$L2_AGGKIT_REST_PORT" \
                '. + {
                    aggkit: {
                        rpc: {
                            internal: ("http://aggkit-" + $prefix + ":5576"),
                            external: ("http://localhost:" + $rpc_port)
                        },
                        rest_api: {
                            internal: ("http://aggkit-" + $prefix + ":5577"),
                            external: ("http://localhost:" + $rest_port)
                        }
                    }
                }')
        fi

        # L2 accounts from genesis (exclude OP predeploy contracts)
        L2_GENESIS_FILE="$OUTPUT_DIR/config/$prefix/l2-genesis.json"
        L2_ACCOUNTS=$(extract_genesis_accounts "$L2_GENESIS_FILE" "L2 network $prefix" "true")

        # Add aggkit accounts from keystores
        if [ -f "$AGGKIT_CONFIG" ]; then
            SEQUENCER_KEYSTORE="$OUTPUT_DIR/config/$prefix/sequencer.keystore"
            AGGORACLE_KEYSTORE="$OUTPUT_DIR/config/$prefix/aggoracle.keystore"
            SOVEREIGNADMIN_KEYSTORE="$OUTPUT_DIR/config/$prefix/sovereignadmin.keystore"
            CLAIMSPONSOR_KEYSTORE="$OUTPUT_DIR/config/$prefix/claimsponsor.keystore"

            AGGKIT_ACCOUNTS="[]"

            # Sequencer
            if [ -f "$SEQUENCER_KEYSTORE" ]; then
                SEQUENCER_ADDR=$(extract_keystore_address "$SEQUENCER_KEYSTORE")
                if [ -n "$SEQUENCER_ADDR" ]; then
                    [[ "$SEQUENCER_ADDR" != 0x* ]] && SEQUENCER_ADDR="0x$SEQUENCER_ADDR"
                    AGGKIT_ACCOUNTS=$(echo "$AGGKIT_ACCOUNTS" | jq \
                        --arg addr "$SEQUENCER_ADDR" \
                        '. + [{
                            address: $addr,
                            private_key: "(encrypted in keystore)",
                            description: "L2 Sequencer account (signs L2 blocks)"
                        }]')
                fi
            fi

            # AggOracle
            if [ -f "$AGGORACLE_KEYSTORE" ]; then
                AGGORACLE_ADDR=$(extract_keystore_address "$AGGORACLE_KEYSTORE")
                if [ -n "$AGGORACLE_ADDR" ]; then
                    [[ "$AGGORACLE_ADDR" != 0x* ]] && AGGORACLE_ADDR="0x$AGGORACLE_ADDR"
                    AGGKIT_ACCOUNTS=$(echo "$AGGKIT_ACCOUNTS" | jq \
                        --arg addr "$AGGORACLE_ADDR" \
                        '. + [{
                            address: $addr,
                            private_key: "(encrypted in keystore)",
                            description: "AggOracle account (submits L1 data to L2)"
                        }]')
                fi
            fi

            # SovereignAdmin
            if [ -f "$SOVEREIGNADMIN_KEYSTORE" ]; then
                SOVEREIGNADMIN_ADDR=$(extract_keystore_address "$SOVEREIGNADMIN_KEYSTORE")
                if [ -n "$SOVEREIGNADMIN_ADDR" ]; then
                    [[ "$SOVEREIGNADMIN_ADDR" != 0x* ]] && SOVEREIGNADMIN_ADDR="0x$SOVEREIGNADMIN_ADDR"
                    AGGKIT_ACCOUNTS=$(echo "$AGGKIT_ACCOUNTS" | jq \
                        --arg addr "$SOVEREIGNADMIN_ADDR" \
                        '. + [{
                            address: $addr,
                            private_key: "(encrypted in keystore)",
                            description: "Sovereign Admin account (manages L2 bridge)"
                        }]')
                fi
            fi

            # ClaimSponsor
            if [ -f "$CLAIMSPONSOR_KEYSTORE" ]; then
                CLAIMSPONSOR_ADDR=$(extract_keystore_address "$CLAIMSPONSOR_KEYSTORE")
                if [ -n "$CLAIMSPONSOR_ADDR" ]; then
                    [[ "$CLAIMSPONSOR_ADDR" != 0x* ]] && CLAIMSPONSOR_ADDR="0x$CLAIMSPONSOR_ADDR"
                    AGGKIT_ACCOUNTS=$(echo "$AGGKIT_ACCOUNTS" | jq \
                        --arg addr "$CLAIMSPONSOR_ADDR" \
                        '. + [{
                            address: $addr,
                            private_key: "(encrypted in keystore)",
                            description: "Claim Sponsor account (sponsors bridge claims)"
                        }]')
                fi
            fi

            # Merge with L2 accounts
            L2_ACCOUNTS=$(jq -s '.[0] + .[1]' <(echo "$L2_ACCOUNTS") <(echo "$AGGKIT_ACCOUNTS"))
        fi

        # Build L2 network object
        # Use temp files to avoid "Argument list too long" errors with large account lists
        echo "$L2_CONTRACTS" > "$TEMP_DIR/l2_contracts_${prefix}.json"
        echo "$L2_SERVICES" > "$TEMP_DIR/l2_services_${prefix}.json"
        echo "$L2_ACCOUNTS" > "$TEMP_DIR/l2_accounts_${prefix}.json"

        L2_NETWORK=$(jq -n \
            --arg chain_id "$L2_CHAIN_ID" \
            --slurpfile contracts "$TEMP_DIR/l2_contracts_${prefix}.json" \
            --slurpfile services "$TEMP_DIR/l2_services_${prefix}.json" \
            --slurpfile accounts "$TEMP_DIR/l2_accounts_${prefix}.json" \
            '{
                chain_id: $chain_id,
                contracts: $contracts[0],
                services: $services[0],
                accounts: $accounts[0]
            }')

        # Add to L2_NETWORKS
        # Use temp files to avoid "Argument list too long" errors
        echo "$L2_NETWORK" > "$TEMP_DIR/l2_network_current.json"
        echo "$L2_NETWORKS" > "$TEMP_DIR/l2_networks_current.json"
        L2_NETWORKS=$(jq --arg prefix "$prefix" --slurpfile network "$TEMP_DIR/l2_network_current.json" \
            '. + {($prefix): $network[0]}' "$TEMP_DIR/l2_networks_current.json")

        log "  ✓ L2 network $prefix info collected"
    done
fi

# ============================================================================
# Build Final Summary JSON
# ============================================================================

log "Building final summary.json..."

# Use temp files to avoid "Argument list too long" errors with large network data
echo "$L1_NETWORK" > "$TEMP_DIR/l1_network.json"
echo "$AGGLAYER_INFO" > "$TEMP_DIR/agglayer_info.json"
echo "$L2_NETWORKS" > "$TEMP_DIR/l2_networks.json"

SUMMARY=$(jq -n \
    --arg snapshot_name "$SNAPSHOT_ID" \
    --arg enclave "$ENCLAVE_NAME" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg l1_mnemonic "$DEFAULT_L1_MNEMONIC" \
    --arg l2_mnemonic "$DEFAULT_L2_MNEMONIC" \
    --slurpfile l1 "$TEMP_DIR/l1_network.json" \
    --slurpfile agglayer "$TEMP_DIR/agglayer_info.json" \
    --slurpfile l2_networks "$TEMP_DIR/l2_networks.json" \
    '{
        snapshot_name: $snapshot_name,
        enclave: $enclave,
        created_at: $timestamp,
        networks: {
            l1: $l1[0],
            agglayer: $agglayer[0],
            l2_networks: $l2_networks[0]
        },
        test_accounts: {
            l1_mnemonic: $l1_mnemonic,
            l2_mnemonic: $l2_mnemonic,
            note: "Pre-funded test accounts are derived from these mnemonics. Use with cast: cast wallet address --mnemonic \"<mnemonic>\" --mnemonic-index <0-N>"
        },
        notes: {
            accounts: "Only accounts with meaningful balances are included. Precompile addresses (0x0000...00xx) and OP predeploy contracts (0x4200...) are excluded. Private keys for keystores are encrypted.",
            services: "Internal URLs are for use within the Docker network. External URLs are for access from the host machine.",
            contracts: "Contract addresses are extracted from configuration files. Some fields may be null if not found."
        }
    }')

# Write to file
SUMMARY_FILE="$OUTPUT_DIR/summary.json"
echo "$SUMMARY" | jq '.' > "$SUMMARY_FILE"

log "✓ Summary generated: $SUMMARY_FILE"

# Pretty print summary
log ""
log "Summary overview:"
log "  L1 Chain ID: $L1_CHAIN_ID"
log "  L1 Services: $(echo "$L1_SERVICES" | jq -r 'keys | length') service(s)"
log "  L1 Accounts: $(echo "$L1_ACCOUNTS" | jq 'length')"

if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "  Agglayer: Present"
fi

if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    log "  L2 Networks: $L2_CHAINS_COUNT network(s)"
fi

log ""
log "Summary generation complete!"

exit 0
