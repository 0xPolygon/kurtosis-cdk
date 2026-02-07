#!/usr/bin/env bash
# Converts transactions.jsonl to executable bash replay script

set -euo pipefail

TRANSACTIONS_FILE="$1"
OUTPUT_SCRIPT="$2"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

TX_COUNT=$(wc -l < "$TRANSACTIONS_FILE" 2>/dev/null || echo "0")
log "Generating replay script with $TX_COUNT transactions"

# Generate script header with RPC helper functions
cat > "$OUTPUT_SCRIPT" << 'HEADER'
#!/bin/sh
set -e

RPC_URL="${RPC_URL:-http://localhost:8545}"
TX_DELAY="${TX_DELAY:-0.1}"

echo "=========================================="
echo "Transaction Replay Script"
echo "=========================================="

# Wait for geth RPC
echo "Waiting for geth RPC..."
until curl -sf -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "$RPC_URL" > /dev/null 2>&1; do
    sleep 1
done
echo "Geth RPC ready"

# Send transaction and wait for receipt
send_tx() {
    local tx_num="$1"
    local raw_tx="$2"

    echo "Sending tx $tx_num..."

    tx_hash=$(curl -sf -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendRawTransaction\",\"params\":[\"$raw_tx\"],\"id\":1}" \
        "$RPC_URL" | jq -r '.result // empty')

    if [ -z "$tx_hash" ]; then
        echo "  WARNING: TX $tx_num failed to submit"
        return 1
    fi

    echo "  TX $tx_num: $tx_hash"

    # Wait for receipt
    retries=30
    while [ $retries -gt 0 ]; do
        receipt=$(curl -sf -X POST -H "Content-Type: application/json" \
            --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionReceipt\",\"params\":[\"$tx_hash\"],\"id\":1}" \
            "$RPC_URL" | jq -r '.result // empty')

        if [ -n "$receipt" ]; then
            echo "  ✓ TX $tx_num mined"
            break
        fi

        sleep 0.5
        retries=$((retries - 1))
    done

    [ $retries -eq 0 ] && echo "  WARNING: TX $tx_num receipt timeout"
    sleep "$TX_DELAY"
}

echo "Starting transaction replay..."
HEADER

# Add transaction replay calls
tx_num=0
while IFS= read -r line; do
    raw_tx=$(echo "$line" | jq -r '.raw_tx')
    echo "send_tx $tx_num \"$raw_tx\"" >> "$OUTPUT_SCRIPT"
    tx_num=$((tx_num + 1))
done < "$TRANSACTIONS_FILE"

# Add footer
cat >> "$OUTPUT_SCRIPT" << 'FOOTER'

echo "=========================================="
echo "Replay complete! Replayed transactions"
echo "=========================================="

# Write completion marker
echo "replay_complete" > /data/geth/.replay_complete
FOOTER

chmod +x "$OUTPUT_SCRIPT"
log "Replay script generated: $OUTPUT_SCRIPT ($TX_COUNT transactions)"
