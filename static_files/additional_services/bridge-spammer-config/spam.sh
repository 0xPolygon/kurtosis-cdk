#!/bin/bash
# This script simulates blockchain activity by sending bridges.
set -e

eth_address=$(cast wallet address --private-key "{{.private_key}}")

# Fund claimtx manager
cast send \
    --legacy \
    --rpc-url "{{.l2_rpc_url}}" \
    --private-key "{{.private_key}}" \
    --value "10ether" \
    "{{.zkevm_l2_claimtxmanager_address}}"

# Deposit on L1 to avoid negative balance
polycli ulxly bridge asset \
    --value "1000000000000000000" \
    --gas-limit "1250000" \
    --bridge-address "{{.zkevm_bridge_address}}" \
    --destination-address "$eth_address" \
    --destination-network 1 \
    --rpc-url "{{.l1_rpc_url}}" \
    --private-key "{{.private_key}}" \
    --chain-id "{{.l1_chain_id}}" \
    --pretty-logs=false

# Allow some time for bridge processing
current_block_number="$(cast block-number --rpc-url '{{.l1_rpc_url}}')"
finalized_block_number=0
until [[ $finalized_block_number -gt $current_block_number ]]; do
    sleep 5
    finalized_block_number="$(cast block-number --rpc-url '{{.l1_rpc_url}}' finalized)"
done

# Start depositing on L2
while true; do
    echo "Running L1-to-L2 Bridge"
    polycli ulxly bridge asset \
        --value "$(date +%s)" \
        --gas-limit "1250000" \
        --bridge-address "{{.zkevm_bridge_address}}" \
        --destination-address "$eth_address" \
        --destination-network 1 \
        --rpc-url "{{.l1_rpc_url}}" \
        --private-key "{{.private_key}}" \
        --chain-id "{{.l1_chain_id}}" \
        --pretty-logs=false
    sleep 1

    echo "Running L2-to-L1 Bridge"
    polycli ulxly bridge asset \
        --value "$(date +%s)" \
        --gas-limit "1250000" \
        --bridge-address "{{with .zkevm_bridge_l2_address}}{{.}}{{else}}{{.zkevm_bridge_address}}{{end}}" \
        --destination-address "$eth_address" \
        --destination-network 0 \
        --rpc-url "{{.l2_rpc_url}}" \
        --private-key "{{.private_key}}" \
        --chain-id "{{.zkevm_rollup_chain_id}}" \
        --pretty-logs=false
    sleep 1
done
