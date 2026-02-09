#!/bin/bash
set -e

# Extract all transactions from L1 geth blocks via RPC
# Usage: ./extract-transactions.sh <GETH_CONTAINER> <OUTPUT_DIR>

GETH_CONTAINER="$1"
OUTPUT_DIR="$2"

if [ -z "$GETH_CONTAINER" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <GETH_CONTAINER> <OUTPUT_DIR>" >&2
    exit 1
fi

TRANSACTIONS_FILE="$OUTPUT_DIR/artifacts/transactions.jsonl"
CHECKPOINT_FILE="$OUTPUT_DIR/artifacts/.tx_extraction_checkpoint"
mkdir -p "$(dirname "$TRANSACTIONS_FILE")"

# Configuration
RPC_TIMEOUT=10  # seconds for wget timeout
RETRY_DELAY=3   # initial delay between retries
MAX_RETRY_DELAY=30  # max delay for exponential backoff
RATE_LIMIT_DELAY=0.1  # delay between blocks to avoid overwhelming geth
PROGRESS_INTERVAL=100  # report progress every N blocks

# Function to call geth RPC with retries and exponential backoff
rpc_call() {
    local method="$1"
    local params="$2"
    local retries=5  # Increased from 3
    local result=""
    local delay=$RETRY_DELAY

    for i in $(seq 1 $retries); do
        result=$(docker exec "$GETH_CONTAINER" wget -q -O - \
            --timeout=$RPC_TIMEOUT \
            --tries=1 \
            --header='Content-Type: application/json' \
            --post-data="{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
            http://localhost:8545 2>/dev/null || echo "")

        if [ -n "$result" ] && echo "$result" | grep -q '"result"'; then
            echo "$result"
            return 0
        fi

        if [ $i -lt $retries ]; then
            echo "RPC call failed (attempt $i/$retries), waiting ${delay}s before retry..." >&2
            sleep $delay
            # Exponential backoff
            delay=$((delay * 2))
            if [ $delay -gt $MAX_RETRY_DELAY ]; then
                delay=$MAX_RETRY_DELAY
            fi
        fi
    done

    echo "RPC call to $method failed after $retries attempts" >&2
    return 1
}

echo "Extracting transactions from geth container: $GETH_CONTAINER"

# Get latest block number
echo "Getting latest block number..."
block_response=$(rpc_call "eth_blockNumber" "[]")
if [ -z "$block_response" ]; then
    echo "Failed to get latest block number" >&2
    exit 1
fi

latest_block_hex=$(echo "$block_response" | docker exec -i "$GETH_CONTAINER" sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
latest_block=$((latest_block_hex))

echo "Latest block: $latest_block"

if [ "$latest_block" -eq 0 ]; then
    echo "No blocks to extract (only genesis block exists)"
    touch "$TRANSACTIONS_FILE"
    rm -f "$CHECKPOINT_FILE"
    exit 0
fi

# Check for existing checkpoint to resume extraction
start_block=1
if [ -f "$CHECKPOINT_FILE" ]; then
    start_block=$(cat "$CHECKPOINT_FILE")
    echo "Resuming from checkpoint: block $start_block"
else
    # Initialize empty transactions file only if starting fresh
    > "$TRANSACTIONS_FILE"
fi

total_txs=0
blocks_processed=0
last_progress_report=$(date +%s)

# Extract transactions from each block
for block_num in $(seq $start_block $latest_block); do
    block_hex=$(printf "0x%x" $block_num)

    # Progress reporting (every N blocks or every 30 seconds)
    blocks_processed=$((blocks_processed + 1))
    current_time=$(date +%s)
    time_since_last_report=$((current_time - last_progress_report))

    if [ $((blocks_processed % PROGRESS_INTERVAL)) -eq 0 ] || [ $time_since_last_report -ge 30 ]; then
        percent=$((block_num * 100 / latest_block))
        echo "Progress: Block $block_num/$latest_block (${percent}%) - $total_txs transactions extracted"
        last_progress_report=$current_time
    fi

    # Get transaction count for this block
    tx_count_response=$(rpc_call "eth_getBlockTransactionCountByNumber" "[\"$block_hex\"]")
    if [ -z "$tx_count_response" ]; then
        echo "Warning: Failed to get transaction count for block $block_num, skipping" >&2
        # Don't fail completely, continue to next block
        echo "$((block_num + 1))" > "$CHECKPOINT_FILE"
        continue
    fi

    tx_count_hex=$(echo "$tx_count_response" | docker exec -i "$GETH_CONTAINER" sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
    tx_count=$((tx_count_hex))

    if [ "$tx_count" -eq 0 ]; then
        # Update checkpoint even for empty blocks
        echo "$((block_num + 1))" > "$CHECKPOINT_FILE"
        # Rate limiting (small delay to avoid overwhelming geth)
        sleep $RATE_LIMIT_DELAY
        continue
    fi

    # Only print block details if it has transactions
    if [ $((blocks_processed % PROGRESS_INTERVAL)) -ne 0 ]; then
        echo "Block $block_num: $tx_count transactions"
    fi

    # Extract each transaction
    for tx_index in $(seq 0 $((tx_count - 1))); do
        tx_index_hex=$(printf "0x%x" $tx_index)

        # Get transaction by block number and index
        tx_response=$(rpc_call "eth_getTransactionByBlockNumberAndIndex" "[\"$block_hex\",\"$tx_index_hex\"]")
        if [ -z "$tx_response" ]; then
            echo "Warning: Failed to get transaction $tx_index from block $block_num" >&2
            continue
        fi

        # Extract transaction hash and from address
        tx_hash=$(echo "$tx_response" | docker exec -i "$GETH_CONTAINER" sed -n 's/.*"hash":"\([^"]*\)".*/\1/p')
        from_addr=$(echo "$tx_response" | docker exec -i "$GETH_CONTAINER" sed -n 's/.*"from":"\([^"]*\)".*/\1/p')

        if [ -z "$tx_hash" ]; then
            echo "Warning: Could not extract hash for transaction $tx_index in block $block_num" >&2
            continue
        fi

        # Default to "unknown" if from address not found
        if [ -z "$from_addr" ]; then
            from_addr="unknown"
        fi

        # Get raw transaction
        raw_tx_response=$(rpc_call "debug_getRawTransaction" "[\"$tx_hash\"]")
        if [ -z "$raw_tx_response" ]; then
            echo "Warning: Failed to get raw transaction $tx_hash" >&2
            continue
        fi

        # Extract raw transaction data
        raw_tx=$(echo "$raw_tx_response" | docker exec -i "$GETH_CONTAINER" sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
        if [ -z "$raw_tx" ]; then
            echo "Warning: Could not extract raw data for transaction $tx_hash" >&2
            continue
        fi

        # Write to JSONL file with sender address
        echo "{\"block\":$block_num,\"tx_index\":$tx_index,\"raw_tx\":\"$raw_tx\",\"from\":\"$from_addr\"}" >> "$TRANSACTIONS_FILE"
        total_txs=$((total_txs + 1))
    done

    # Update checkpoint after successfully processing block
    echo "$((block_num + 1))" > "$CHECKPOINT_FILE"

    # Rate limiting (small delay to avoid overwhelming geth)
    sleep $RATE_LIMIT_DELAY
done

echo "Extraction complete: $total_txs transactions extracted from $blocks_processed blocks"
echo "Output: $TRANSACTIONS_FILE"

# Validate output
if [ ! -f "$TRANSACTIONS_FILE" ]; then
    echo "Error: Transactions file was not created" >&2
    exit 1
fi

if [ "$total_txs" -eq 0 ] && [ "$latest_block" -gt 0 ]; then
    echo "Warning: No transactions extracted despite $latest_block blocks existing" >&2
fi

# Remove checkpoint file on successful completion
rm -f "$CHECKPOINT_FILE"
echo "✓ Transaction extraction completed successfully"

exit 0
