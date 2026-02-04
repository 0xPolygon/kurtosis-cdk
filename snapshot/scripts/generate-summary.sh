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

# Extract accounts from genesis file
extract_genesis_accounts() {
    local genesis_file="$1"
    local description_prefix="$2"

    if [ ! -f "$genesis_file" ]; then
        echo "[]"
        return
    fi

    # Extract accounts with balance
    jq -r --arg desc "$description_prefix" '
        .alloc // {} | to_entries | map({
            address: .key,
            balance: .value.balance,
            description: ($desc + " pre-funded account")
        })
    ' "$genesis_file" 2>/dev/null || echo "[]"
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

# ============================================================================
# Build L1 Network Info
# ============================================================================

log "Building L1 network info..."

# L1 contract addresses (from genesis if available)
L1_CONTRACTS="{}"

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

# Add validator accounts
VALIDATOR_KEYS_DIR="$OUTPUT_DIR/artifacts/validator-keys"
if [ -d "$VALIDATOR_KEYS_DIR" ]; then
    log "  Found validator keys directory"
    # List all validator public keys
    VALIDATOR_PUBKEYS=$(ls -1 "$VALIDATOR_KEYS_DIR" 2>/dev/null | grep "^0x" || echo "")
    if [ -n "$VALIDATOR_PUBKEYS" ]; then
        VALIDATOR_COUNT=$(echo "$VALIDATOR_PUBKEYS" | wc -l)
        log "  Found $VALIDATOR_COUNT validator(s)"

        # Add validator accounts to L1_ACCOUNTS
        VALIDATOR_ACCOUNTS=$(echo "$VALIDATOR_PUBKEYS" | jq -R -s -c '
            split("\n") | map(select(length > 0)) | map({
                address: .,
                private_key: "",
                description: "Validator pubkey (private key in keystore)"
            })
        ')

        L1_ACCOUNTS=$(jq -s '.[0] + .[1]' <(echo "$L1_ACCOUNTS") <(echo "$VALIDATOR_ACCOUNTS"))
    fi
fi

# Build L1 network object
L1_NETWORK=$(jq -n \
    --argjson contracts "$L1_CONTRACTS" \
    --argjson services "$L1_SERVICES" \
    --argjson accounts "$L1_ACCOUNTS" \
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
        contracts: $contracts,
        services: $services,
        accounts: $accounts
    }')

# ============================================================================
# Build Agglayer Info (if present)
# ============================================================================

AGGLAYER_INFO="null"

if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "Building Agglayer info..."

    AGGLAYER_CONFIG="$OUTPUT_DIR/config/agglayer/config.toml"

    # Extract contract addresses from agglayer config
    AGGLAYER_CONTRACTS="{}"
    if [ -f "$AGGLAYER_CONFIG" ]; then
        # Extract key contract addresses using grep and sed
        ROLLUP_MANAGER=$(grep -m1 "rollup-manager-contract" "$AGGLAYER_CONFIG" | sed 's/.*= *"\([^"]*\)".*/\1/' 2>/dev/null || echo "")
        GER_CONTRACT=$(grep -m1 "polygon-zkevm-global-exit-root-v2-contract" "$AGGLAYER_CONFIG" | sed 's/.*= *"\([^"]*\)".*/\1/' 2>/dev/null || echo "")

        AGGLAYER_CONTRACTS=$(jq -n \
            --arg rollup_manager "$ROLLUP_MANAGER" \
            --arg ger "$GER_CONTRACT" \
            '{
                rollup_manager: (if $rollup_manager != "" then $rollup_manager else null end),
                global_exit_root_v2: (if $ger != "" then $ger else null end)
            }')
    fi

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

    # Agglayer accounts
    AGGLAYER_ACCOUNTS="[]"
    AGGREGATOR_KEYSTORE="$OUTPUT_DIR/config/agglayer/aggregator.keystore"
    if [ -f "$AGGREGATOR_KEYSTORE" ]; then
        AGGREGATOR_ADDR=$(extract_keystore_address "$AGGREGATOR_KEYSTORE")
        if [ -n "$AGGREGATOR_ADDR" ]; then
            # Add 0x prefix if not present
            [[ "$AGGREGATOR_ADDR" != 0x* ]] && AGGREGATOR_ADDR="0x$AGGREGATOR_ADDR"

            AGGLAYER_ACCOUNTS=$(jq -n \
                --arg addr "$AGGREGATOR_ADDR" \
                '[{
                    address: $addr,
                    private_key: "(encrypted in keystore)",
                    description: "Agglayer aggregator account"
                }]')
        fi
    fi

    AGGLAYER_INFO=$(jq -n \
        --argjson contracts "$AGGLAYER_CONTRACTS" \
        --argjson services "$AGGLAYER_SERVICES" \
        --argjson accounts "$AGGLAYER_ACCOUNTS" \
        '{
            contracts: $contracts,
            services: $services,
            accounts: $accounts
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

        # Extract contract addresses from rollup.json
        L2_CONTRACTS="{}"
        if [ -f "$ROLLUP_FILE" ]; then
            # System config and other addresses from rollup config
            SYSTEM_CONFIG=$(jq -r '.genesis.system_config // empty' "$ROLLUP_FILE" 2>/dev/null || echo "")

            L2_CONTRACTS=$(jq -n --arg system_config "$SYSTEM_CONFIG" '{
                system_config: (if $system_config != "" then $system_config else null end)
            }')
        fi

        # Extract additional contract addresses from aggkit config
        AGGKIT_CONFIG="$OUTPUT_DIR/config/$prefix/aggkit-config.toml"
        if [ -f "$AGGKIT_CONFIG" ]; then
            # Extract bridge addresses and other contracts
            L1_BRIDGE=$(grep -m1 "^BridgeAddr" "$AGGKIT_CONFIG" | cut -d'"' -f2 2>/dev/null || echo "")
            L2_BRIDGE=$(grep -A10 "^\[L2Config\]" "$AGGKIT_CONFIG" | grep "^BridgeAddr" | cut -d'"' -f2 2>/dev/null || echo "")
            ROLLUP_MANAGER=$(grep "RollupManagerAddr" "$AGGKIT_CONFIG" | cut -d'"' -f2 2>/dev/null || echo "")
            GER_CONTRACT=$(grep "GlobalExitRootAddr" "$AGGKIT_CONFIG" | cut -d'"' -f2 2>/dev/null || echo "")

            # Merge with existing contracts
            L2_CONTRACTS=$(echo "$L2_CONTRACTS" | jq \
                --arg l1_bridge "$L1_BRIDGE" \
                --arg l2_bridge "$L2_BRIDGE" \
                --arg rollup_manager "$ROLLUP_MANAGER" \
                --arg ger "$GER_CONTRACT" \
                '. + {
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

        # L2 accounts from genesis
        L2_GENESIS_FILE="$OUTPUT_DIR/config/$prefix/l2-genesis.json"
        L2_ACCOUNTS=$(extract_genesis_accounts "$L2_GENESIS_FILE" "L2 network $prefix")

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
        L2_NETWORK=$(jq -n \
            --arg chain_id "$L2_CHAIN_ID" \
            --argjson contracts "$L2_CONTRACTS" \
            --argjson services "$L2_SERVICES" \
            --argjson accounts "$L2_ACCOUNTS" \
            '{
                chain_id: $chain_id,
                contracts: $contracts,
                services: $services,
                accounts: $accounts
            }')

        # Add to L2_NETWORKS
        L2_NETWORKS=$(echo "$L2_NETWORKS" | jq --arg prefix "$prefix" --argjson network "$L2_NETWORK" \
            '. + {($prefix): $network}')

        log "  ✓ L2 network $prefix info collected"
    done
fi

# ============================================================================
# Build Final Summary JSON
# ============================================================================

log "Building final summary.json..."

SUMMARY=$(jq -n \
    --arg snapshot_name "$SNAPSHOT_ID" \
    --arg enclave "$ENCLAVE_NAME" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson l1 "$L1_NETWORK" \
    --argjson agglayer "$AGGLAYER_INFO" \
    --argjson l2_networks "$L2_NETWORKS" \
    '{
        snapshot_name: $snapshot_name,
        enclave: $enclave,
        created_at: $timestamp,
        networks: {
            l1: $l1,
            agglayer: $agglayer,
            l2_networks: $l2_networks
        },
        notes: {
            accounts: "Private keys in keystores are encrypted. Use keystore files with appropriate tools to decrypt.",
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
