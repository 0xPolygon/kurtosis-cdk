#!/bin/bash
set -e

# Generate executable replay script from transactions.jsonl
# Usage: ./generate-replay-script.sh <OUTPUT_DIR>

OUTPUT_DIR="$1"

if [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <OUTPUT_DIR>" >&2
    exit 1
fi

TRANSACTIONS_FILE="$OUTPUT_DIR/artifacts/transactions.jsonl"
REPLAY_SCRIPT="$OUTPUT_DIR/artifacts/replay-transactions.sh"

if [ ! -f "$TRANSACTIONS_FILE" ]; then
    echo "Error: Transactions file not found: $TRANSACTIONS_FILE" >&2
    exit 1
fi

echo "Generating replay script from $TRANSACTIONS_FILE"

# Count transactions
tx_count=$(wc -l < "$TRANSACTIONS_FILE" | tr -d ' ')
echo "Found $tx_count transactions to replay"

# Generate script header
cat > "$REPLAY_SCRIPT" << 'EOF'
#!/bin/sh
set -e

RPC_URL="${RPC_URL:-http://geth:8545}"

echo "Waiting for geth RPC to be ready..."

# Wait for geth RPC (timeout after 60 seconds)
for i in $(seq 1 60); do
    if wget -q -O - --timeout=2 --tries=1 \
        --header='Content-Type: application/json' \
        --post-data='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC_URL" > /dev/null 2>&1; then
        echo "Geth RPC is ready"
        break
    fi

    if [ "$i" -eq 60 ]; then
        echo "Error: Geth RPC did not become ready within 60 seconds" >&2
        exit 1
    fi

    sleep 1
done

echo "Waiting for block production to start..."

# Wait for blocks to be produced (block number > 0)
for i in $(seq 1 120); do
    block_response=$(wget -q -O - --timeout=2 --tries=1 \
        --header='Content-Type: application/json' \
        --post-data='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC_URL" 2>/dev/null || echo "")

    if [ -n "$block_response" ]; then
        block_num=$(echo "$block_response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
        if [ -n "$block_num" ] && [ "$block_num" != "0x0" ]; then
            echo "Block production started (block: $block_num)"
            # Wait a few more seconds for block production to stabilize
            sleep 3
            break
        fi
    fi

    if [ "$i" -eq 120 ]; then
        echo "Error: Block production did not start within 120 seconds" >&2
        exit 1
    fi

    sleep 1
done

echo "Starting transaction replay..."

# Function to send transaction and wait for it to be mined
send_tx() {
    local tx_num="$1"
    local raw_tx="$2"
    local max_wait=60  # Maximum 60 seconds to wait for mining

    echo "[TX $tx_num] Sending transaction..."

    # Send transaction
    response=$(wget -q -O - --timeout=10 --tries=3 \
        --header='Content-Type: application/json' \
        --post-data='{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["'"$raw_tx"'"],"id":1}' \
        "$RPC_URL" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "[TX $tx_num] ERROR: Failed to send transaction (no response from RPC)" >&2
        echo "[TX $tx_num] Raw TX: $raw_tx" >&2
        return 1
    fi

    # Check for error in response
    if echo "$response" | grep -q '"error"'; then
        error_code=$(echo "$response" | sed -n 's/.*"code":\([^,}]*\).*/\1/p')
        error_msg=$(echo "$response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')

        echo "[TX $tx_num] ERROR: Transaction rejected by node" >&2
        echo "[TX $tx_num]   Error code: $error_code" >&2
        echo "[TX $tx_num]   Error message: $error_msg" >&2
        echo "[TX $tx_num]   Raw TX: $raw_tx" >&2
        echo "[TX $tx_num]   Full response: $response" >&2

        # Check if it's a blob transaction (which we can't replay)
        if echo "$error_msg" | grep -qi "blob"; then
            echo "[TX $tx_num] SKIP: Blob transaction cannot be replayed (missing sidecar)" >&2
            return 0  # Don't fail on blob transactions
        fi

        return 1
    fi

    # Extract transaction hash from response
    tx_hash=$(echo "$response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')

    if [ -z "$tx_hash" ]; then
        echo "[TX $tx_num] ERROR: No transaction hash in response" >&2
        echo "[TX $tx_num]   Response: $response" >&2
        return 1
    fi

    echo "[TX $tx_num] Transaction sent: $tx_hash"
    echo "[TX $tx_num] Waiting for transaction to be mined (max ${max_wait}s)..."

    # Wait for transaction to be mined (check every second)
    for i in $(seq 1 $max_wait); do
        receipt=$(wget -q -O - --timeout=5 --tries=1 \
            --header='Content-Type: application/json' \
            --post-data='{"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":["'"$tx_hash"'"],"id":1}' \
            "$RPC_URL" 2>/dev/null || echo "")

        # Check if receipt exists and is not null
        if [ -n "$receipt" ] && echo "$receipt" | grep -q '"result":{' && ! echo "$receipt" | grep -q '"result":null'; then
            # Extract block number and status
            block_num=$(echo "$receipt" | sed -n 's/.*"blockNumber":"\([^"]*\)".*/\1/p')
            status=$(echo "$receipt" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')

            if [ "$status" = "0x1" ]; then
                echo "[TX $tx_num] ✓ MINED successfully in block $block_num (waited ${i}s)"
                return 0
            else
                echo "[TX $tx_num] ERROR: Transaction REVERTED in block $block_num" >&2
                echo "[TX $tx_num]   TX hash: $tx_hash" >&2
                echo "[TX $tx_num]   Receipt: $receipt" >&2
                return 1
            fi
        fi

        # Show progress every 10 seconds
        if [ $((i % 10)) -eq 0 ]; then
            echo "[TX $tx_num] Still waiting... (${i}s elapsed)"
        fi

        sleep 1
    done

    # Timeout - check if transaction is still pending
    pending_check=$(wget -q -O - --timeout=5 --tries=1 \
        --header='Content-Type: application/json' \
        --post-data='{"jsonrpc":"2.0","method":"eth_getTransactionByHash","params":["'"$tx_hash"'"],"id":1}' \
        "$RPC_URL" 2>/dev/null || echo "")

    echo "[TX $tx_num] ERROR: Transaction timed out after ${max_wait}s" >&2
    echo "[TX $tx_num]   TX hash: $tx_hash" >&2
    echo "[TX $tx_num]   Pending check: $pending_check" >&2
    return 1
}

EOF

# Add transaction tracking
cat >> "$REPLAY_SCRIPT" << 'EOF'

echo "========================================"
echo "Starting Sequential Transaction Replay"
echo "========================================"
echo ""

# Track transaction successes and failures
total_txs=0
successful_txs=0
failed_txs=0
skipped_txs=0

EOF

# Add transaction replay calls
tx_num=1
while IFS= read -r line; do
    # Extract raw_tx from JSON line
    raw_tx=$(echo "$line" | sed -n 's/.*"raw_tx":"\([^"]*\)".*/\1/p')

    if [ -z "$raw_tx" ]; then
        echo "Warning: Could not extract raw_tx from line $tx_num" >&2
        tx_num=$((tx_num + 1))
        continue
    fi

    # Add transaction to script - WAIT for each to be mined before continuing
    cat >> "$REPLAY_SCRIPT" << EOFTX
total_txs=\$((total_txs + 1))
if send_tx $tx_num "$raw_tx"; then
    # Check if it was skipped (blob tx) or successful
    if grep -q "SKIP:" /tmp/last_tx_log 2>/dev/null; then
        skipped_txs=\$((skipped_txs + 1))
    else
        successful_txs=\$((successful_txs + 1))
    fi
else
    failed_txs=\$((failed_txs + 1))
    echo "[REPLAY] FATAL: Transaction $tx_num failed - stopping replay" >&2
    echo "[REPLAY] This is a critical failure. Check logs above for details." >&2
    exit 1
fi
EOFTX

    tx_num=$((tx_num + 1))
done < "$TRANSACTIONS_FILE"

# Add script footer with summary
cat >> "$REPLAY_SCRIPT" << 'EOF'

echo ""
echo "========================================"
echo "Transaction Replay Complete"
echo "========================================"
echo "  Total transactions: $total_txs"
echo "  Successfully mined: $successful_txs"
echo "  Skipped (blob txs): $skipped_txs"
echo "  Failed: $failed_txs"
echo ""

if [ "$failed_txs" -eq 0 ]; then
    echo "✓ All transactions replayed successfully!"
    exit 0
else
    echo "✗ Transaction replay failed with $failed_txs failures" >&2
    exit 1
fi
EOF

# Make script executable
chmod +x "$REPLAY_SCRIPT"

echo "Replay script generated: $REPLAY_SCRIPT"

# Validate script syntax
if ! sh -n "$REPLAY_SCRIPT" 2>&1; then
    echo "Error: Generated replay script has syntax errors" >&2
    exit 1
fi

echo "Replay script syntax validated successfully"

exit 0
