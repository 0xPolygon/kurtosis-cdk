#!/bin/bash

# This script monitors the verification progress of zkEVM batches.

# Check if the required arguments are provided.
if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <verified_batches_target> <timeout> [rpc_service]"
  exit 1
fi

# The number of batches to be verified.
verified_batches_target="$1"

# The script timeout (in seconds).
timeout="$2"

# Name of RPC service to query
rpc_service="$3"

if [[ -z "$rpc_service" ]]; then
  rpc_service="zkevm-node-rpc-001"
fi

start_time=$(date +%s)
end_time=$((start_time + timeout))

rpc_url="$(kurtosis port print cdk-v1 $rpc_service http-rpc)"
while true; do
  verified_batches="$(cast to-dec "$(cast rpc --rpc-url "$rpc_url" zkevm_verifiedBatchNumber | sed 's/"//g')")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verified Batches: $verified_batches"

  current_time=$(date +%s)
  if (( current_time > end_time )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
    exit 1
  fi

  if (( verified_batches > verified_batches_target )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Exiting... $verified_batches batches were verified!"
    exit 0
  fi

  sleep 10
done