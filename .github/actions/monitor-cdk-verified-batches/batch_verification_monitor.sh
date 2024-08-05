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
pk="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"

# We need to send a first bridge tx in order to force erigon to update the l1infotreeroot because the first batch has a bug in erigon
cast send --legacy --rpc-url "$rpc_url" --private-key "$pk" --gas-limit 643528 --create 0x600160015B810190630000000456

while true; do
  verified_batches="$(cast to-dec "$(cast rpc --rpc-url "$rpc_url" zkevm_verifiedBatchNumber | sed 's/"//g')")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verified Batches: $verified_batches"

  # This is here to take up some space within the batch in order to make sure the batches actually increase during the duration of the test
  cast send --legacy --rpc-url "$rpc_url" --private-key "$pk" --gas-limit 643528 --create 0x600160015B810190630000000456

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
