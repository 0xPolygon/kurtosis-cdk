#!/bin/bash
set -e

# This script simulates blockchain activity by sending bridges.

# Deposit on L1 to avoid negative balance
spammer_value="50ether"
l1_wei_deposit_amount=$(echo "$spammer_value" | sed 's/ether//g' | cast to-wei)
l1_wei_deposit_amount=$(echo "scale=0; $l1_wei_deposit_amount * 95 / 100" | bc)
polycli ulxly bridge asset \
    --value "$l1_wei_deposit_amount" \
    --gas-limit "1250000" \
    --bridge-address "{{.zkevm_bridge_address}}" \
    --destination-address "{{.address}}" \
    --destination-network 1 \
    --rpc-url "{{.l1_rpc_url}}" \
    --private-key "{{.private_key}}" \
    --chain-id "{{.l1_chain_id}}" \
    --pretty-logs=false

# Allow some time for bridge processing
sleep 10

# Start depositing on L2
l2_wei_deposit_amount=1
while true; do
    polycli ulxly bridge asset \
        --value "$l2_wei_deposit_amount" \
        --gas-limit "1250000" \
        --bridge-address "{{.zkevm_bridge_address}}" \
        --destination-address "{{.address}}" \
        --destination-network 0 \
        --rpc-url "{{.l2_rpc_url}}" \
        --private-key "{{.private_key}}" \
        --chain-id "{{.zkevm_rollup_chain_id}}" \
        --pretty-logs=false
    sleep 1
done
