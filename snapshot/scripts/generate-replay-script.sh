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

# Function to send transaction (without waiting for confirmation)
send_tx() {
    local tx_num="$1"
    local raw_tx="$2"

    # Send transaction
    response=$(wget -q -O - --timeout=10 --tries=3 \
        --header='Content-Type: application/json' \
        --post-data='{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["'"$raw_tx"'"],"id":1}' \
        "$RPC_URL" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "[TX $tx_num] ERROR: Failed to send transaction (no response from RPC)" >&2
        return 1
    fi

    # Check for error in response
    if echo "$response" | grep -q '"error"'; then
        error_code=$(echo "$response" | sed -n 's/.*"code":\([^,}]*\).*/\1/p')
        error_msg=$(echo "$response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')

        # Check if it's a blob transaction (which we can skip)
        if echo "$error_msg" | grep -qi "blob"; then
            echo "SKIP"  # Return special marker for skipped transactions
            return 0
        fi

        echo "[TX $tx_num] ERROR: Transaction rejected by node" >&2
        echo "[TX $tx_num]   Error code: $error_code" >&2
        echo "[TX $tx_num]   Error message: $error_msg" >&2
        return 1
    fi

    # Extract and return transaction hash
    tx_hash=$(echo "$response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')

    if [ -z "$tx_hash" ]; then
        echo "[TX $tx_num] ERROR: No transaction hash in response" >&2
        return 1
    fi

    echo "$tx_hash"
    return 0
}

# Function to wait for a transaction to be mined
wait_for_tx() {
    local tx_num="$1"
    local tx_hash="$2"
    local max_wait=120  # Maximum 120 seconds to wait for mining

    # Wait for transaction to be mined (check every 2 seconds)
    for i in $(seq 1 $max_wait); do
        receipt=$(wget -q -O - --timeout=5 --tries=1 \
            --header='Content-Type: application/json' \
            --post-data='{"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":["'"$tx_hash"'"],"id":1}' \
            "$RPC_URL" 2>/dev/null || echo "")

        # Check if receipt exists and is not null
        if [ -n "$receipt" ] && echo "$receipt" | grep -q '"result":{' && ! echo "$receipt" | grep -q '"result":null'; then
            # Extract status
            status=$(echo "$receipt" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')

            if [ "$status" = "0x1" ]; then
                block_num=$(echo "$receipt" | sed -n 's/.*"blockNumber":"\([^"]*\)".*/\1/p')
                echo "[TX $tx_num] ✓ Mined in block $block_num"
                return 0
            else
                echo "[TX $tx_num] ERROR: Transaction REVERTED" >&2
                echo "[TX $tx_num]   TX hash: $tx_hash" >&2
                return 1
            fi
        fi

        sleep 2
    done

    echo "[TX $tx_num] ERROR: Transaction timed out after ${max_wait}s" >&2
    echo "[TX $tx_num]   TX hash: $tx_hash" >&2
    return 1
}

EOF

# Add transaction tracking and replay logic
cat >> "$REPLAY_SCRIPT" << 'EOF'

echo "========================================"
echo "Parallel Transaction Replay"
echo "========================================"
echo ""

# Track transaction successes and failures
total_txs=0
successful_txs=0
failed_txs=0
skipped_txs=0

# Arrays to store transaction hashes and numbers (using space-separated strings)
tx_hashes=""
tx_numbers=""

EOF

# Generate Phase 1: Send all transactions
cat >> "$REPLAY_SCRIPT" << 'EOF'
echo "Phase 1: Sending all transactions in order..."
echo ""

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

    # Add transaction send to script
    cat >> "$REPLAY_SCRIPT" << EOFTX
total_txs=\$((total_txs + 1))
echo "[TX $tx_num] Sending transaction..."
tx_hash=\$(send_tx $tx_num "$raw_tx")
tx_result=\$?

if [ \$tx_result -eq 0 ]; then
    if [ "\$tx_hash" = "SKIP" ]; then
        echo "[TX $tx_num] Skipped (blob transaction)"
        skipped_txs=\$((skipped_txs + 1))
    else
        echo "[TX $tx_num] Sent: \$tx_hash"
        tx_hashes="\$tx_hashes \$tx_hash"
        tx_numbers="\$tx_numbers $tx_num"
    fi
else
    failed_txs=\$((failed_txs + 1))
    echo "[REPLAY] FATAL: Failed to send transaction $tx_num" >&2
    exit 1
fi

EOFTX

    tx_num=$((tx_num + 1))
done < "$TRANSACTIONS_FILE"

# Generate Phase 2: Wait for all transactions
cat >> "$REPLAY_SCRIPT" << 'EOF'

echo ""
echo "========================================"
echo "Phase 2: Waiting for all transactions to be mined..."
echo "========================================"
echo ""

# Convert space-separated strings to proper arrays
tx_hash_list=$tx_hashes
tx_num_list=$tx_numbers

# Count pending transactions
pending_count=$(echo "$tx_hash_list" | wc -w)
echo "Waiting for $pending_count transactions to be mined..."
echo ""

# Wait for each transaction
for tx_hash in $tx_hash_list; do
    # Get corresponding transaction number
    tx_num=$(echo "$tx_num_list" | cut -d' ' -f1)
    tx_num_list=$(echo "$tx_num_list" | cut -d' ' -f2-)

    if wait_for_tx "$tx_num" "$tx_hash"; then
        successful_txs=$((successful_txs + 1))
    else
        failed_txs=$((failed_txs + 1))
        echo "[REPLAY] FATAL: Transaction $tx_num failed to mine" >&2
        exit 1
    fi
done

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
