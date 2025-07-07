#!/usr/bin/env bash
set -uo pipefail

# This script sends various transactions to the RPC.

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
if [[ -z "${RPC_URL}" ]]; then
  log_error "RPC_URL environment variable is not set"
  exit 1
fi
log_info "PRIVATE_KEY: $PRIVATE_KEY"
log_info "RPC_URL: $RPC_URL"

# Function to handle errors and continue execution.
handle_error() {
  log_error "An error occurred. Continuing execution."
}
trap handle_error ERR

# Continuously send load to the rpc.
while true; do
  log_info "Sending transactions to the rpc"
  polycli loadtest \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --legacy \
    --requests "50000" \
    --concurrency "10" \
    --rate-limit "50" \
    --eth-amount "1" \
    --pretty-logs=false

  log_info "Completed batch. Waiting 60 seconds before next batch."
  sleep 60
done
