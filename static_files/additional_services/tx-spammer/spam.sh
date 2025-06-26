#!/usr/bin/env bash
set -uxo pipefail

# This script simulates blockchain activity by sending transactions and making RPC calls.

# Function to handle errors and continue execution.
handle_error() {
  echo "An error occurred. Continuing execution..."
}
trap handle_error ERR

# Checking environment variables.
if [[ -z "${PRIVATE_KEY}" ]]; then
  echo "Error: PRIVATE_KEY environment variable is not set"
  exit 1
fi
if [[ -z "${RPC_URL}" ]]; then
  echo "Error: RPC_URL environment variable is not set"
  exit 1
fi
echo "PRIVATE_KEY: $PRIVATE_KEY"
echo "RPC_URL: $RPC_URL"

# Sending load to the rpc.
while true; do
  echo "Sending transactions to the rpc..."
  polycli loadtest \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --legacy \
    --verbosity 700 \
    --mode t,2 \
    --requests "50000" \
    --concurrency "5" \
    --rate-limit "50" \
    --eth-amount "0.000000000000000001"

  echo "Making rpc calls..."
  polycli rpcfuzz \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --verbosity 700

  echo "Waiting 60 seconds before sending more transactions..."
  sleep 60
done
