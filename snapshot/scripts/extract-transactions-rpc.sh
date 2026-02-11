#!/bin/bash
set -e

# Extract transactions from geth via external RPC
# Usage: ./extract-transactions-rpc.sh <RPC_URL> <OUTPUT_DIR> <START_BLOCK> <END_BLOCK>

RPC_URL="$1"
OUTPUT_DIR="$2"
START_BLOCK="${3:-1}"
END_BLOCK="$4"

if [ -z "$RPC_URL" ] || [ -z "$OUTPUT_DIR" ] || [ -z "$END_BLOCK" ]; then
    echo "Usage: $0 <RPC_URL> <OUTPUT_DIR> [START_BLOCK] <END_BLOCK>" >&2
    exit 1
fi

TRANSACTIONS_FILE="$OUTPUT_DIR/transactions.jsonl"
mkdir -p "$OUTPUT_DIR"

echo "Extracting transactions from blocks $START_BLOCK to $END_BLOCK..."

# Initialize/clear transactions file
> "$TRANSACTIONS_FILE"

total_txs=0

# Extract transactions from each block
for block_num in $(seq $START_BLOCK $END_BLOCK); do
    block_hex=$(printf "0x%x" $block_num)
    
    # Get transaction count in block
    tx_count_response=$(cast rpc --rpc-url "$RPC_URL" eth_getBlockTransactionCountByNumber "$block_hex" 2>/dev/null || echo "")
    
    if [ -z "$tx_count_response" ]; then
        echo "Warning: Failed to get tx count for block $block_num, skipping"
        continue
    fi
    
    tx_count_hex=$(echo "$tx_count_response" | sed 's/"//g')
    tx_count=$((tx_count_hex))
    
    if [ "$tx_count" -eq 0 ]; then
        continue
    fi
    
    # Extract each transaction in the block
    for tx_index in $(seq 0 $((tx_count - 1))); do
        tx_index_hex=$(printf "0x%x" $tx_index)
        
        # Get raw transaction
        tx_response=$(cast rpc --rpc-url "$RPC_URL" eth_getTransactionByBlockNumberAndIndex "$block_hex" "$tx_index_hex" 2>/dev/null || echo "")
        
        if [ -n "$tx_response" ] && echo "$tx_response" | grep -q '"result"'; then
            # Extract the transaction object
            tx_obj=$(echo "$tx_response" | jq -r '.result')
            
            # Get sender address and raw tx
            from_addr=$(echo "$tx_obj" | jq -r '.from')
            
            # Build raw transaction - we need to reconstruct it from the transaction object
            # For replay, we actually need the signed raw transaction, which requires different approach
            # For now, store the transaction details
            echo "{\"block\":$block_num,\"tx_index\":$tx_index,\"from\":\"$from_addr\",\"tx\":$tx_obj}" >> "$TRANSACTIONS_FILE"
            total_txs=$((total_txs + 1))
        fi
    done
    
    if [ $((block_num % 100)) -eq 0 ]; then
        echo "Processed block $block_num/$END_BLOCK ($total_txs transactions so far)"
    fi
done

echo "✅ Extracted $total_txs transactions to $TRANSACTIONS_FILE"
