#!/bin/bash

# This script monitors the verification progress of zkEVM batches.
# It queries a specified RPC URL and tracks the number of verified batches.

# Function to display usage information.
usage() {
  echo "Usage: $0 --rpc-url <URL> --target <TARGET> --timeout <TIMEOUT>"
  echo "  --rpc-url: The RPC URL to query."
  echo "  --target:  The target number of verified batches."
  echo "  --timeout: The script timeout in seconds."
  exit 1
}

# Initialize variables.
rpc_url=""
target="10"
timeout="900" # 15 minutes.

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  --rpc-url)
    rpc_url="$2"
    shift 2
    ;;
  --target)
    target="$2"
    shift 2
    ;;
  --timeout)
    timeout="$2"
    shift 2
    ;;
  *)
    usage
    ;;
  esac
done

# Check if the required argument is provided.
if [ -z "$rpc_url" ]; then
  echo "Error: RPC URL is required."
  usage
fi

# Print script parameters for debug purposes.
echo "Running script with values:"
echo "- RPC URL: $rpc_url"
echo "- Target: $target"
echo "- Timeout: $timeout"
echo

# Calculate the end time based on the current time and the specified timeout.
start_time=$(date +%s)
end_time=$((start_time + timeout))

# Main loop to monitor batch verification.
while true; do
  # Query the number of verified batches from the RPC URL.
  batch_number="$(cast to-dec "$(cast rpc --rpc-url "$rpc_url" zkevm_batchNumber | sed 's/"//g')")"
  virtual_batch_number="$(cast to-dec "$(cast rpc --rpc-url "$rpc_url" zkevm_virtualBatchNumber | sed 's/"//g')")"
  verified_batch_number="$(cast to-dec "$(cast rpc --rpc-url "$rpc_url" zkevm_verifiedBatchNumber | sed 's/"//g')")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Latest Batch: $batch_number, Virtual Batch: $virtual_batch_number, Verified Batch: $verified_batch_number"

  # Check if the verified batches target has been reached.
  if ((verified_batch_number > target)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Exiting... More than $target batches were verified!"
    exit 0
  fi

  # Check if the timeout has been reached.
  current_time=$(date +%s)
  if ((current_time > end_time)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
    exit 1
  fi

  echo "Sending a transaction to increase the batch number..."
  cast send \
    --legacy \
    --rpc-url "$rpc_url" \
    --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    --gas-limit 100000 \
    --create 0x600160015B810190630000000456

  echo "Waiting a few seconds before the next iteration..."
  echo
  sleep 10
done
