#!/bin/bash

# This script simulates blockchain activity by sending bridges.

set -e

claimtx_value="10ether"
spammer_value="50ether"

l1_wei_deposit_amount=$(echo "$spammer_value" | sed 's/ether//g' | cast to-wei)
l1_wei_deposit_amount=$(echo "scale=0; $l1_wei_deposit_amount * 95 / 100" | bc)
l2_wei_deposit_amount=1

# Fund claimtx manager
cast send \
    --legacy \
    --rpc-url "{{.l2_rpc_url}}" \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --value "$claimtx_value" \
    "{{.zkevm_l2_claimtxmanager_address}}"

# Create and fund test account
cast wallet new --json | jq '.[0]' | tee .spam.wallet.json

eth_address="$(jq -r '.address' .spam.wallet.json)"
private_key="$(jq -r '.private_key' .spam.wallet.json)"

until cast send --legacy --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}" --value "$spammer_value" "$eth_address"; do
  echo "Attempting to fund a test account on L1 for the bridge spammer"
done

until cast send --legacy --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l2_rpc_url}}" --value "$spammer_value" "$eth_address"; do
  echo "Attempting to fund a test account on L2 for the bridge spammer"
done

# Deposit on L1 to avoid negative balance
polycli ulxly bridge asset \
    --value "$l1_wei_deposit_amount" \
    --gas-limit "1250000" \
    --bridge-address "{{.zkevm_bridge_address}}" \
    --destination-address "$eth_address" \
    --destination-network 1 \
    --rpc-url "{{.l1_rpc_url}}" \
    --private-key "$private_key" \
    --chain-id "{{.l1_chain_id}}" \
    --pretty-logs=false

# Allow some time for bridge processing
sleep 10

# Start depositing on L2
while true; do
    polycli ulxly bridge asset \
        --value "$l2_wei_deposit_amount" \
        --gas-limit "1250000" \
        --bridge-address "{{.zkevm_bridge_address}}" \
        --destination-address "$eth_address" \
        --destination-network 0 \
        --rpc-url "{{.l2_rpc_url}}" \
        --private-key "$private_key" \
        --chain-id "{{.zkevm_rollup_chain_id}}" \
        --pretty-logs=false
    sleep 1
done
