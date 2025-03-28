#!/bin/bash
# This script simulates blockchain activity by sending bridges.
set -e

claimtx_value="10ether"
spammer_value="50ether"

l2_admin_private_key="{{.zkevm_l2_admin_private_key}}"
l2_admin_balance=$(cast balance --rpc-url "{{.l2_rpc_url}}" "$(cast wallet address --private-key "$l2_admin_private_key")")
if [[ $l2_admin_balance -eq 0 ]]; then
    l2_admin_private_key=$(cast wallet private-key --mnemonic 'test test test test test test test test test test test junk')
fi


# Fund claimtx manager
cast send \
    --legacy \
    --rpc-url "{{.l2_rpc_url}}" \
    --private-key "$l2_admin_private_key" \
    --value "$claimtx_value" \
    "{{.zkevm_l2_claimtxmanager_address}}"

# Create and fund test account
cast wallet new --json | jq '.[0]' | tee .spam.wallet.json

eth_address="$(jq -r '.address' .spam.wallet.json)"
private_key="$(jq -r '.private_key' .spam.wallet.json)"

until cast send --legacy --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}" --value "$spammer_value" "$eth_address"; do
  echo "Attempting to fund a test account on L1 for the bridge spammer"
done

until cast send --legacy --private-key "$l2_admin_private_key" --rpc-url "{{.l2_rpc_url}}" --value "$spammer_value" "$eth_address"; do
  echo "Attempting to fund a test account on L2 for the bridge spammer"
done

# Deposit on L1 to avoid negative balance
polycli ulxly bridge asset \
    --value "1000000000000000000" \
    --gas-limit "1250000" \
    --bridge-address "{{.zkevm_bridge_address}}" \
    --destination-address "$eth_address" \
    --destination-network 1 \
    --rpc-url "{{.l1_rpc_url}}" \
    --private-key "$private_key" \
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
        --private-key "$private_key" \
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
        --private-key "$private_key" \
        --chain-id "{{.zkevm_rollup_chain_id}}" \
        --pretty-logs=false
    sleep 1
done
