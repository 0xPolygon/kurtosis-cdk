#!/bin/bash

# This script simulates blockchain activity by sending transactions and making RPC calls.

set -e

# Spam parameters.
requests=50000
concurrency=5
rate_limit=50

while true; do
  echo "Sending a few transactions to the RPC..."
  polycli loadtest \
    --rpc-url "{{.rpc_url}}" \
    --private-key "{{.private_key}}" \
    --legacy \
    --verbosity 700 \
    --mode t,2 \
    --requests "$requests" \
    --concurrency "$concurrency" \
    --rate-limit "$rate_limit"

  echo "Making a few RPC calls..."
  polycli rpcfuzz \
    --rpc-url "{{.rpc_url}}" \
    --private-key "{{.private_key}}" \
    --verbosity 700

  echo "Waiting 60 seconds before sending more transactions..."
  sleep 60
done
