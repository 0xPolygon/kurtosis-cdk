#!/bin/bash
# This script simulates blockchain activity by perfoming L1 to L2 and L2 to L1 bridges.
set -e

# Checking environment variables.
if [[ -z "${PRIVATE_KEY}" ]]; then
  echo "Error: PRIVATE_KEY environment variable is not set"
  exit 1
fi
if [[ -z "${L1_CHAIN_ID}" ]]; then
  echo "Error: L1_CHAIN_ID environment variable is not set"
  exit 1
fi
if [[ -z "${L1_RPC_URL}" ]]; then
  echo "Error: L1_RPC_URL environment variable is not set"
  exit 1
fi
if [[ -z "${L2_CHAIN_ID}" ]]; then
  echo "Error: L2_CHAIN_ID environment variable is not set"
  exit 1
fi
if [[ -z "${L2_RPC_URL}" ]]; then
  echo "Error: L2_RPC_URL environment variable is not set"
  exit 1
fi
if [[ -z "${L2_CLAIM_TX_MANAGER_ADDRESS}" ]]; then
  echo "Error: L2_CLAIM_TX_MANAGER_ADDRESS environment variable is not set"
  exit 1
fi
if [[ -z "${L1_BRIDGE_ADDRESS}" ]]; then
  echo "Error: L1_BRIDGE_ADDRESS environment variable is not set"
  exit 1
fi
if [[ -z "${L2_BRIDGE_ADDRESS}" ]]; then
  echo "Error: L2_BRIDGE_ADDRESS environment variable is not set"
  exit 1
fi
echo "PRIVATE_KEY: $PRIVATE_KEY"
echo "L1_CHAIN_ID: $L1_CHAIN_ID"
echo "L1_RPC_URL: $L1_RPC_URL"
echo "L2_CHAIN_ID: $L2_CHAIN_ID"
echo "L2_RPC_URL: $L2_RPC_URL"
echo "L2_CLAIM_TX_MANAGER_ADDRESS: $L2_CLAIM_TX_MANAGER_ADDRESS"
echo "L1_BRIDGE_ADDRESS: $L1_BRIDGE_ADDRESS"
echp "L2_BRIDGE_ADDRESS: $L2_BRIDGE_ADDRESS"

# Derive address from private key.
eth_address=$(cast wallet address --private-key "$PRIVATE_KEY")
echo "eth_address: $eth_address"

# Fund claimtx manager.
# TODO: This step should not be part of the spammer script, it should be done elsewhere.
cast send --legacy --rpc-url "$L2_RPC_URL" --private-key "$PRIVATE_KEY" --value "10ether" "$L2_CLAIM_TX_MANAGER_ADDRESS"

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

# Allow some time for bridge processing.
current_block_number="$(cast block-number --rpc-url $L1_RPC_URL)"
finalized_block_number=0
until [[ "$finalized_block_number" -gt "$current_block_number" ]]; do
    sleep 5
    finalized_block_number="$(cast block-number --rpc-url $L1_RPC_URL finalized)"
done

# Start depositing on L2.
while true; do
    echo "Bridging from L1 to L2"
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

    echo "Bridging from L2 to L1"
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
