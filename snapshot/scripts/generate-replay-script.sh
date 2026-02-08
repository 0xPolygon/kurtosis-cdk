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

# Function to send transaction (without waiting for mining)
send_tx_only() {
    local tx_num="$1"
    local raw_tx="$2"

    # Send transaction
    response=$(wget -q -O - --timeout=10 --tries=3 \
        --header='Content-Type: application/json' \
        --post-data='{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["'"$raw_tx"'"],"id":1}' \
        "$RPC_URL" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "ERROR:no_response"
        return 1
    fi

    # Check for error in response
    if echo "$response" | grep -q '"error"'; then
        error_code=$(echo "$response" | sed -n 's/.*"code":\([^,}]*\).*/\1/p')
        error_msg=$(echo "$response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')

        # Check if it's a blob transaction (skip these)
        if echo "$error_msg" | grep -qi "blob"; then
            echo "SKIP:blob"
            return 0
        fi

        # Check if it's insufficient funds (retryable)
        if echo "$error_msg" | grep -qi "insufficient funds\|insufficient balance"; then
            echo "RETRY:insufficient_funds"
            return 2  # Special return code for retryable errors
        fi

        # Check if transaction already known (already in mempool/mined)
        if echo "$error_msg" | grep -qi "already known\|nonce too low\|replacement transaction underpriced"; then
            echo "SKIP:already_known"
            return 0
        fi

        # Other errors are fatal
        echo "ERROR:$error_code:$error_msg"
        return 1
    fi

    # Extract transaction hash from response
    tx_hash=$(echo "$response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')

    if [ -z "$tx_hash" ]; then
        echo "ERROR:no_hash"
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
echo "Optimized Transaction Replay with Retry"
echo "========================================"
echo ""

# Track transaction successes and failures
total_txs=0
successful_txs=0
failed_txs=0
skipped_txs=0

# Storage for pending transactions (space-separated)
pending_tx_nums=""
pending_tx_hashes=""
pending_raw_txs=""

EOF

# Generate Phase 1: Send all transactions (with retry queue)
cat >> "$REPLAY_SCRIPT" << 'EOF'
echo "Phase 1: Sending all transactions (with retry for failures)..."
echo ""

MAX_RETRIES=10
retry_delay=2  # Start with 2 second delay

EOF

# Add all transactions to the script
tx_num=1
while IFS= read -r line; do
    # Extract raw_tx from JSON line
    raw_tx=$(echo "$line" | sed -n 's/.*"raw_tx":"\([^"]*\)".*/\1/p')

    if [ -z "$raw_tx" ]; then
        echo "Warning: Could not extract raw_tx from line $tx_num" >&2
        tx_num=$((tx_num + 1))
        continue
    fi

    # Add transaction data to the script
    cat >> "$REPLAY_SCRIPT" << EOFTX

# Transaction $tx_num
total_txs=\$((total_txs + 1))
tx_${tx_num}_raw="$raw_tx"
tx_${tx_num}_pending=1

EOFTX

    tx_num=$((tx_num + 1))
done < "$TRANSACTIONS_FILE"

# Add retry loop logic
cat >> "$REPLAY_SCRIPT" << 'EOF'

# Retry loop - attempt to send all pending transactions
for retry_attempt in $(seq 0 $MAX_RETRIES); do
    if [ "$retry_attempt" -gt 0 ]; then
        echo ""
        echo "Retry attempt $retry_attempt of $MAX_RETRIES (waiting ${retry_delay}s for dependencies)..."
        sleep $retry_delay

        # Increase delay for next retry (exponential backoff, max 10s)
        retry_delay=$((retry_delay * 2))
        if [ $retry_delay -gt 10 ]; then
            retry_delay=10
        fi
    fi

    pending_count=0
    retry_needed=0

EOF

# Add send logic for each transaction
tx_num=1
while IFS= read -r line; do
    raw_tx=$(echo "$line" | sed -n 's/.*"raw_tx":"\([^"]*\)".*/\1/p')
    if [ -z "$raw_tx" ]; then
        tx_num=$((tx_num + 1))
        continue
    fi

    cat >> "$REPLAY_SCRIPT" << EOFTX

    # Try to send transaction $tx_num
    if [ "\$tx_${tx_num}_pending" -eq 1 ]; then
        pending_count=\$((pending_count + 1))
        echo "[TX $tx_num] Sending transaction..."

        result=\$(send_tx_only $tx_num "\$tx_${tx_num}_raw")
        result_code=\$?

        if [ \$result_code -eq 0 ]; then
            if echo "\$result" | grep -q "^SKIP:"; then
                reason=\$(echo "\$result" | cut -d: -f2)
                echo "[TX $tx_num] Skipped (\$reason)"
                skipped_txs=\$((skipped_txs + 1))
                tx_${tx_num}_pending=0
            elif echo "\$result" | grep -q "^ERROR:"; then
                error=\$(echo "\$result" | cut -d: -f2-)
                echo "[TX $tx_num] ERROR: \$error" >&2
                failed_txs=\$((failed_txs + 1))
                tx_${tx_num}_pending=0
                echo "[REPLAY] FATAL: Transaction $tx_num failed permanently" >&2
                exit 1
            else
                # Got a transaction hash
                echo "[TX $tx_num] Sent: \$result"
                pending_tx_nums="\$pending_tx_nums $tx_num"
                pending_tx_hashes="\$pending_tx_hashes \$result"
                tx_${tx_num}_pending=0
            fi
        elif [ \$result_code -eq 2 ]; then
            # Retryable error (insufficient funds)
            echo "[TX $tx_num] Insufficient funds - will retry"
            retry_needed=1
        else
            # Fatal error
            echo "[TX $tx_num] ERROR: \$result" >&2
            failed_txs=\$((failed_txs + 1))
            tx_${tx_num}_pending=0
            echo "[REPLAY] FATAL: Transaction $tx_num failed permanently" >&2
            exit 1
        fi
    fi
EOFTX

    tx_num=$((tx_num + 1))
done < "$TRANSACTIONS_FILE"

# Add retry completion check
cat >> "$REPLAY_SCRIPT" << 'EOF'

    # Check if we need to retry
    if [ $retry_needed -eq 0 ]; then
        echo ""
        echo "All transactions sent successfully!"
        break
    fi

    if [ "$retry_attempt" -eq "$MAX_RETRIES" ]; then
        echo ""
        echo "[REPLAY] ERROR: Max retries ($MAX_RETRIES) exceeded" >&2
        echo "[REPLAY] Some transactions still have insufficient funds" >&2
        exit 1
    fi
done

# Phase 2: Wait for all transactions to be mined
echo ""
echo "========================================"
echo "Phase 2: Waiting for transactions to be mined..."
echo "========================================"
echo ""

# Convert space-separated strings to lists
tx_hash_list=$pending_tx_hashes
tx_num_list=$pending_tx_nums

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
