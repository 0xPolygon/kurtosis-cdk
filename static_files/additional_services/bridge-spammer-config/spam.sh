#!/bin/bash
# This script simulates blockchain activity by sending bridges.
set -e

eth_address=$(cast wallet address --private-key "$PRIVATE_KEY")

# Fund claimtx manager.
cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --value "10ether" "$L2_CLAIM_TX_MANAGER_ADDRESS}}"

# Deposit on L1 to avoid negative balance.
polycli ulxly bridge asset \
    --value "1000000000000000000" \
    --gas-limit "1250000" \
    --bridge-address "$L1_BRIDGE_ADDRESS" \
    --destination-address "$eth_address" \
    --destination-network 1 \
    --rpc-url "$L1_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --chain-id "$L1_CHAIN_ID" \
    --pretty-logs=false

# Allow some time for bridge processing
current_block_number="$(cast block-number --rpc-url $L1_RPC_URL)"
finalized_block_number=0
until [[ $finalized_block_number -gt $current_block_number ]]; do
    sleep 5
    finalized_block_number="$(cast block-number --rpc-url $L1_RPC_URL finalized)"
done

# Start depositing on L2
while true; do
    echo "Running L1-to-L2 Bridge"
    polycli ulxly bridge asset \
        --value "$(date +%s)" \
        --gas-limit "1250000" \
        --bridge-address "$L1_BRIDGE_ADDRESS" \
        --destination-address "$eth_address" \
        --destination-network 1 \
        --rpc-url "$L1_RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --chain-id "$L1_CHAIN_ID" \
        --pretty-logs=false
    sleep 1

    echo "Running L2-to-L1 Bridge"
    polycli ulxly bridge asset \
        --value "$(date +%s)" \
        --gas-limit "1250000" \
        --bridge-address "$L2_BRIDGE_ADDRESS" \
        --destination-address "$eth_address" \
        --destination-network 0 \
        --rpc-url "$L2_RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --chain-id "$L2_CHAIN_ID" \
        --pretty-logs=false
    sleep 1
done
