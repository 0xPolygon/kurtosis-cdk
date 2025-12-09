#!/usr/bin/env bash
set -uo pipefail

# This script simulates blockchain activity by performing L1 to L2 and L2 to L1 bridges.

# Helper function to log messages in JSON format.
log_error() {
  echo "{\"error\": \"$1\"}"
}

log_info() {
  echo "{\"info\": \"$1\"}"
}

# Checking environment variables.
if [[ -z "${PRIVATE_KEY}" ]]; then
  log_error "PRIVATE_KEY environment variable is not set"
  exit 1
fi
if [[ -z "${L1_CHAIN_ID}" ]]; then
  log_error "L1_CHAIN_ID environment variable is not set"
  exit 1
fi
if [[ -z "${L1_RPC_URL}" ]]; then
  log_error "L1_RPC_URL environment variable is not set"
  exit 1
fi
if [[ -z "${L2_CHAIN_ID}" ]]; then
  log_error "L2_CHAIN_ID environment variable is not set"
  exit 1
fi
if [[ -z "${L2_RPC_URL}" ]]; then
  log_error "L2_RPC_URL environment variable is not set"
  exit 1
fi
if [[ -z "${L1_BRIDGE_ADDRESS}" ]]; then
  log_error "L1_BRIDGE_ADDRESS environment variable is not set"
  exit 1
fi
if [[ -z "${L2_BRIDGE_ADDRESS}" ]]; then
  log_error "L2_BRIDGE_ADDRESS environment variable is not set"
  exit 1
fi
log_info "PRIVATE_KEY: $PRIVATE_KEY"
log_info "L1_CHAIN_ID: $L1_CHAIN_ID"
log_info "L1_RPC_URL: $L1_RPC_URL"
log_info "L2_CHAIN_ID: $L2_CHAIN_ID"
log_info "L2_RPC_URL: $L2_RPC_URL"
log_info "L1_BRIDGE_ADDRESS: $L1_BRIDGE_ADDRESS"
log_info "L2_BRIDGE_ADDRESS: $L2_BRIDGE_ADDRESS"
log_info "L2_NETWORK_ID: $L2_NETWORK_ID"

# Derive address from private key.
eth_address=$(cast wallet address --private-key "$PRIVATE_KEY")
log_info "eth_address: $eth_address"

# Function to handle errors and continue execution.
handle_error() {
  log_error "An error occurred. Continuing execution..."
}
trap handle_error ERR

# Deposit on L1 to avoid negative balance.
log_info "Depositing on L1 to avoid negative balances"
polycli ulxly bridge asset \
  --value "1000000000000000000" \
  --gas-limit "1250000" \
  --bridge-address "$L1_BRIDGE_ADDRESS" \
  --destination-address "$eth_address" \
  --destination-network "$L2_NETWORK_ID" \
  --rpc-url "$L1_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --chain-id "$L1_CHAIN_ID" \
  --pretty-logs=false

# Allow some time for bridge processing.
current_block_number="$(cast block-number --rpc-url "$L1_RPC_URL")"
finalized_block_number=0
until [[ "$finalized_block_number" -gt "$current_block_number" ]]; do
  sleep 5
  finalized_block_number="$(cast block-number --rpc-url "$L1_RPC_URL" finalized)"
done

# Start depositing on L2 and back to L1.
while true; do
  log_info "Bridging from L1 to L2"
  polycli ulxly bridge asset \
    --value "$(date +%s)" \
    --gas-limit "1250000" \
    --bridge-address "$L1_BRIDGE_ADDRESS" \
    --destination-address "$eth_address" \
    --destination-network "$L2_NETWORK_ID" \
    --rpc-url "$L1_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --chain-id "$L1_CHAIN_ID" \
    --pretty-logs=false
  sleep 60
  log_info "Bridging from L2 to L1"
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
