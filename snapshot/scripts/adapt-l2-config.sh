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

    # Update only the L1 genesis to current L1 block
    # This prevents op-node from trying to sync old L2 blocks from historical L1 batches
    # Note: We keep the original l2_time to match the actual L2 genesis file
    jq --arg block "$CURRENT_L1_BLOCK" --arg hash "$CURRENT_L1_HASH" '
        .genesis.l1.number = ($block | tonumber) |
        .genesis.l1.hash = $hash
    ' "$ROLLUP_FILE.bak" > "$ROLLUP_FILE"
    log "    ✓ Updated L1 genesis: block $CURRENT_L1_BLOCK"

    log "    ✓ Originals saved to *.bak"
    log "    NOTE: L2 genesis file (l2-genesis.json) remains unchanged to preserve genesis hash"
done

log "L2 configuration adaptation complete"
log ""
log "NOTE: L2 will start from genesis with L1 origin at current block"
log "      This prevents syncing historical L2 blocks that don't have state"

exit 0
