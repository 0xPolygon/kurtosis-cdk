#!/bin/bash

# This script simulates blockchain activity by sending transactions and making RPC calls.

set -e

# Spam parameters.
requests=50000
concurrency=5
rate_limit=50
spammer_value="10ether"

cast wallet new --json | jq '.[0]' | tee .spam.wallet.json

eth_address="$(jq -r '.address' .spam.wallet.json)"
private_key="$(jq -r '.private_key' .spam.wallet.json)"

until cast send --legacy --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.rpc_url}}" --value "$spammer_value" "$eth_address"; do
  echo "Attempting to fund a test account for the tx spammer"
done

while true; do
  echo "Sending a few transactions to the RPC..."
  polycli loadtest \
    --rpc-url "{{.rpc_url}}" \
    --private-key "$private_key" \
    --legacy \
    --verbosity 700 \
    --mode t,2 \
    --requests "$requests" \
    --concurrency "$concurrency" \
    --rate-limit "$rate_limit" \
    --eth-amount "0.000000000000000001"

  echo "Making a few RPC calls..."
  polycli rpcfuzz \
    --rpc-url "{{.rpc_url}}" \
    --private-key "$private_key" \
    --verbosity 700

  echo "Waiting 60 seconds before sending more transactions..."
  sleep 60
done
