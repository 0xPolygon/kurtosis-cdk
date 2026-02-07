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

# Function to send transaction and wait for receipt
send_tx() {
    local tx_num="$1"
    local raw_tx="$2"

    # Send transaction
    response=$(wget -q -O - --timeout=5 --tries=3 \
        --header='Content-Type: application/json' \
        --post-data='{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["'"$raw_tx"'"],"id":1}' \
        "$RPC_URL" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "Warning: Failed to send transaction $tx_num" >&2
        return 1
    fi

    # Check for error in response
    if echo "$response" | grep -q '"error"'; then
        error_msg=$(echo "$response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')

        # Ignore "already known" and "replacement transaction underpriced" errors
        if echo "$error_msg" | grep -qi "already known\|replacement transaction underpriced"; then
            return 0
        fi

        echo "Warning: Transaction $tx_num failed: $error_msg" >&2
        return 1
    fi

    # Extract transaction hash from response
    tx_hash=$(echo "$response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')

    if [ -z "$tx_hash" ]; then
        echo "Warning: No transaction hash returned for transaction $tx_num" >&2
        return 1
    fi

    # Wait for receipt (15 second timeout, check every 0.5 seconds)
    for i in $(seq 1 30); do
        receipt=$(wget -q -O - --timeout=2 --tries=1 \
            --header='Content-Type: application/json' \
            --post-data='{"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":["'"$tx_hash"'"],"id":1}' \
            "$RPC_URL" 2>/dev/null || echo "")

        # Check if receipt exists and is not null
        if [ -n "$receipt" ] && echo "$receipt" | grep -q '"result":{' && ! echo "$receipt" | grep -q '"result":null'; then
            # Log progress every 10 transactions
            if [ $((tx_num % 10)) -eq 0 ] || [ "$tx_num" -eq 1 ]; then
                echo "Replayed transaction $tx_num (tx: $tx_hash)"
            fi
            return 0
        fi

        sleep 0.5
    done

    echo "Warning: Transaction $tx_num timed out waiting for receipt" >&2
    return 1
}

EOF

# Add transaction tracking
cat >> "$REPLAY_SCRIPT" << 'EOF'

# Track transaction successes and failures
total_txs=0
successful_txs=0
failed_txs=0

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

    # Add transaction to script with success tracking
    cat >> "$REPLAY_SCRIPT" << EOFTX
total_txs=\$((total_txs + 1))
if send_tx $tx_num "$raw_tx"; then
    successful_txs=\$((successful_txs + 1))
else
    failed_txs=\$((failed_txs + 1))
fi
EOFTX

    tx_num=$((tx_num + 1))
done < "$TRANSACTIONS_FILE"

# Add script footer with summary
cat >> "$REPLAY_SCRIPT" << 'EOF'

echo ""
echo "Transaction replay summary:"
echo "  Total: $total_txs"
echo "  Successful: $successful_txs"
echo "  Failed: $failed_txs"

# Exit with success if at least 80% of transactions succeeded
success_rate=$((successful_txs * 100 / total_txs))
if [ "$success_rate" -ge 80 ]; then
    echo "Transaction replay completed successfully (${success_rate}% success rate)"
    exit 0
else
    echo "Transaction replay failed (only ${success_rate}% success rate)" >&2
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
