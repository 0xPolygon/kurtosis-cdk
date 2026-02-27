#!/usr/bin/env bash
#
# Adapt L2 Configuration Script
# Updates rollup.json to start from current L1 state instead of historical blocks
#
# Usage: adapt-l2-config.sh <OUTPUT_DIR> <DISCOVERY_JSON> <CHECKPOINT_JSON>
#

set -euo pipefail

# Check arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <OUTPUT_DIR> <DISCOVERY_JSON> <CHECKPOINT_JSON>" >&2
    exit 1
fi

OUTPUT_DIR="$1"
DISCOVERY_JSON="$2"
CHECKPOINT_JSON="$3"

# L1 client types (override via environment variables)
L1_EL_TYPE="${L1_EL_TYPE:-reth}"
L1_CL_TYPE="${L1_CL_TYPE:-lighthouse}"
L1_EL_SERVICE="el-1-${L1_EL_TYPE}-${L1_CL_TYPE}"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Adapting L2 configurations for snapshot..."

# Get current L1 block info from checkpoint
CURRENT_L1_BLOCK=$(jq -r '.l1_state.block_number' "$CHECKPOINT_JSON")
CURRENT_L1_HASH=$(jq -r '.l1_state.block_hash' "$CHECKPOINT_JSON")

if [ -z "$CURRENT_L1_BLOCK" ] || [ "$CURRENT_L1_BLOCK" = "null" ]; then
    log "ERROR: Could not read current L1 block from checkpoint"
    exit 1
fi

log "Current L1 state: block $CURRENT_L1_BLOCK ($CURRENT_L1_HASH)"

# Get L1 block timestamp from checkpoint.json
L1_TIMESTAMP=$(jq -r '.l1_state.block_timestamp // empty' "$CHECKPOINT_JSON" 2>/dev/null || echo "")

if [ -z "$L1_TIMESTAMP" ] || [ "$L1_TIMESTAMP" = "null" ] || [ "$L1_TIMESTAMP" = "" ]; then
    log "WARNING: L1 block timestamp not found in checkpoint, trying RPC query..."

    # Fallback: Try to query from RPC
    L1_RPC_URL="http://localhost:8545"
    L1_TIMESTAMP_HEX=$(curl -s -X POST "$L1_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"0x$(printf '%x' "$CURRENT_L1_BLOCK")\",false],\"id\":1}" \
        | jq -r '.result.timestamp // empty' 2>/dev/null || echo "")

    if [ -n "$L1_TIMESTAMP_HEX" ] && [ "$L1_TIMESTAMP_HEX" != "null" ]; then
        # Convert hex to decimal
        L1_TIMESTAMP=$((16#${L1_TIMESTAMP_HEX#0x}))
    else
        log "WARNING: Could not fetch L1 block timestamp, L2 timestamps will not be updated"
        L1_TIMESTAMP=""
    fi
fi

if [ -n "$L1_TIMESTAMP" ] && [ "$L1_TIMESTAMP" != "null" ]; then
    log "L1 block timestamp: $L1_TIMESTAMP"
fi

# Check if we have L2 chains
L2_CHAINS_COUNT=$(jq -r '.l2_chains | length // 0' "$DISCOVERY_JSON" 2>/dev/null || echo "0")

if [ "$L2_CHAINS_COUNT" = "null" ] || [ "$L2_CHAINS_COUNT" -eq 0 ]; then
    log "No L2 chains found, skipping L2 config adaptation"
    exit 0
fi

log "Adapting $L2_CHAINS_COUNT L2 network(s)..."

for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
    log "  Processing L2 network: $prefix"

    ROLLUP_FILE="$OUTPUT_DIR/config/$prefix/rollup.json"
    L2_GENESIS_FILE="$OUTPUT_DIR/config/$prefix/l2-genesis.json"

    if [ ! -f "$ROLLUP_FILE" ]; then
        log "    WARNING: rollup.json not found, skipping"
        continue
    fi

    # Backup originals
    cp "$ROLLUP_FILE" "$ROLLUP_FILE.bak"
    if [ -f "$L2_GENESIS_FILE" ]; then
        cp "$L2_GENESIS_FILE" "$L2_GENESIS_FILE.bak"
    fi

    # Update L1 genesis to current L1 block and update l2_time to match L1 timestamp
    # This prevents op-node from trying to sync old L2 blocks from historical L1 batches
    # and ensures L2 genesis time is not before L1 origin time
    if [ -n "$L1_TIMESTAMP" ] && [ "$L1_TIMESTAMP" != "null" ]; then
        # Add 1 second to L1 timestamp to ensure L2 time is after L1 time
        L2_TIME=$((L1_TIMESTAMP + 1))

        # Update rollup.json
        jq --arg block "$CURRENT_L1_BLOCK" --arg hash "$CURRENT_L1_HASH" --arg l2time "$L2_TIME" '
            .genesis.l1.number = ($block | tonumber) |
            .genesis.l1.hash = $hash |
            .genesis.l2_time = ($l2time | tonumber)
        ' "$ROLLUP_FILE.bak" > "$ROLLUP_FILE"
        log "    ✓ Updated L1 genesis: block $CURRENT_L1_BLOCK"
        log "    ✓ Updated L2 genesis time: $L2_TIME (L1 time + 1s)"

        # Update l2-genesis.json timestamp to match and compute new genesis hash
        if [ -f "$L2_GENESIS_FILE" ]; then
            L2_TIME_HEX=$(printf "0x%x" "$L2_TIME")
            jq --arg timestamp "$L2_TIME_HEX" '.timestamp = $timestamp' "$L2_GENESIS_FILE.bak" > "$L2_GENESIS_FILE"
            log "    ✓ Updated L2 genesis file timestamp: $L2_TIME_HEX"

            # Add account allocations for aggoracle, sovereignadmin, and claimsponsor
            # These accounts need funds to send transactions on L2
            log "    Adding account allocations to L2 genesis..."

            # Default funding amount: 100 ether = 100000000000000000000 wei = 0x56bc75e2d63100000
            FUNDING_AMOUNT="0x56bc75e2d63100000"

            # Addresses from input_parser.star
            AGGORACLE_ADDR="0x0b68058E5b2592b1f472AdFe106305295A332A7C"
            SOVEREIGNADMIN_ADDR="0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16"
            CLAIMSPONSOR_ADDR="0x635243A11B41072264Df6c9186e3f473402F94e9"

            # Add allocations using jq
            jq --arg aggoracle "$AGGORACLE_ADDR" \
               --arg sovereignadmin "$SOVEREIGNADMIN_ADDR" \
               --arg claimsponsor "$CLAIMSPONSOR_ADDR" \
               --arg balance "$FUNDING_AMOUNT" '
                .alloc[$aggoracle] = {"balance": $balance} |
                .alloc[$sovereignadmin] = {"balance": $balance} |
                .alloc[$claimsponsor] = {"balance": $balance}
            ' "$L2_GENESIS_FILE" > "$L2_GENESIS_FILE.tmp"
            mv "$L2_GENESIS_FILE.tmp" "$L2_GENESIS_FILE"
            log "    ✓ Added allocations for aggoracle, sovereignadmin, and claimsponsor"

            # Compute new genesis hash using geth in a temporary container
            log "    Computing new L2 genesis hash..."

            # Get the op-geth image from discovery
            OP_GETH_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_geth_sequencer.image // empty" "$DISCOVERY_JSON" 2>/dev/null || echo "")

            if [ -z "$OP_GETH_IMAGE" ]; then
                log "    ⚠ WARNING: Could not find op-geth image, using default"
                OP_GETH_IMAGE="us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101411.3"
            fi

            # Create temp directory for genesis init
            TEMP_DIR=$(mktemp -d)
            cp "$L2_GENESIS_FILE" "$TEMP_DIR/genesis.json"

            # Initialize genesis and extract the hash using geth console
            NEW_L2_HASH=$(docker run --rm --entrypoint /bin/sh \
                -v "$TEMP_DIR:/tmp/genesis-init" \
                "$OP_GETH_IMAGE" \
                -c "geth init --datadir=/tmp/datadir /tmp/genesis-init/genesis.json >/dev/null 2>&1 && geth --datadir=/tmp/datadir --exec 'eth.getBlock(0).hash' console 2>/dev/null | head -1" \
                | tr -d '"' || echo "")

            # Clean up temp directory
            rm -rf "$TEMP_DIR"

            if [ -n "$NEW_L2_HASH" ] && [ "$NEW_L2_HASH" != "null" ] && [[ "$NEW_L2_HASH" == 0x* ]]; then
                log "    ✓ Computed new L2 genesis hash: $NEW_L2_HASH"

                # Update rollup.json with new genesis hash
                jq --arg hash "$NEW_L2_HASH" '.genesis.l2.hash = $hash' "$ROLLUP_FILE" > "$ROLLUP_FILE.tmp"
                mv "$ROLLUP_FILE.tmp" "$ROLLUP_FILE"
                log "    ✓ Updated rollup.json with new L2 genesis hash"
            else
                log "    ⚠ WARNING: Failed to compute L2 genesis hash - op-node may fail to start"
                log "    ⚠ You may need to manually update genesis.l2.hash in rollup.json"
            fi
        fi
    else
        jq --arg block "$CURRENT_L1_BLOCK" --arg hash "$CURRENT_L1_HASH" '
            .genesis.l1.number = ($block | tonumber) |
            .genesis.l1.hash = $hash
        ' "$ROLLUP_FILE.bak" > "$ROLLUP_FILE"
        log "    ✓ Updated L1 genesis: block $CURRENT_L1_BLOCK"
        log "    ⚠ WARNING: Could not update L2 genesis time (L1 timestamp not available)"
    fi

    log "    ✓ Originals saved to *.bak"

    # ========================================================================
    # Adapt aggkit config if present
    # ========================================================================

    AGGKIT_CONFIG="$OUTPUT_DIR/config/$prefix/aggkit-config.toml"

    if [ -f "$AGGKIT_CONFIG" ]; then
        log "  Adapting aggkit configuration for docker-compose..."

        # Backup original
        cp "$AGGKIT_CONFIG" "$AGGKIT_CONFIG.bak"

        # Replace Kurtosis container names with docker-compose service names
        # L1: el-1-<el_type>-<cl_type> -> geth
        # L2 geth: op-el-1-op-geth-op-node-<prefix> -> op-geth-<prefix>
        # op-node: op-cl-1-op-node-op-geth-<prefix> -> op-node-<prefix>

        sed -i "s|http://${L1_EL_SERVICE}:8545|http://geth:8545|g" "$AGGKIT_CONFIG"
        sed -i "s|http://op-el-1-op-geth-op-node-$prefix:8545|http://op-geth-$prefix:8545|g" "$AGGKIT_CONFIG"
        sed -i "s|http://op-cl-1-op-node-op-geth-$prefix:8547|http://op-node-$prefix:8547|g" "$AGGKIT_CONFIG"

        log "    ✓ aggkit config adapted for docker-compose"
        log "    ✓ Original saved to aggkit-config.toml.bak"
    else
        log "    No aggkit config found, skipping"
    fi
done

# ========================================================================
# Adapt agglayer config if present
# ========================================================================

AGGLAYER_CONFIG="$OUTPUT_DIR/config/agglayer/config.toml"

if [ -f "$AGGLAYER_CONFIG" ]; then
    log "Adapting agglayer configuration for docker-compose..."

    # Backup original if not already backed up
    if [ ! -f "$AGGLAYER_CONFIG.bak" ]; then
        cp "$AGGLAYER_CONFIG" "$AGGLAYER_CONFIG.bak"
    fi

    # Replace Kurtosis L2 RPC endpoints with docker-compose service names
    # Pattern: op-el-1-op-geth-op-node-<prefix> -> op-geth-<prefix>
    # Need to update all L2 networks in the [full-node-rpcs] section

    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        sed -i "s|http://op-el-1-op-geth-op-node-$prefix:8545|http://op-geth-$prefix:8545|g" "$AGGLAYER_CONFIG"
        log "  ✓ Updated L2 RPC endpoint for network $prefix"
    done

    log "✓ agglayer config adapted for docker-compose"
    log "✓ Original saved to config/agglayer/config.toml.bak"
else
    log "No agglayer config found, skipping"
fi

log "L2 configuration adaptation complete"
log ""
log "NOTE: L2 will start from genesis with L1 origin at current block"
log "      This prevents syncing historical L2 blocks that don't have state"

exit 0
