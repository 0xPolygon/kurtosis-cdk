#!/bin/bash

# This script monitors the verification progress of zkEVM batches.
# It queries a specified RPC URL and tracks the number of batches.

# Function to display usage information.
usage() {
  echo "Usage: $0 --enclave <ENCLAVE> --rpc-url <URL> --target <TARGET> --timeout <TIMEOUT>"
  echo "  --enclave: The name of the Kurtosis enclave."
  echo "  --rpc-url: The RPC URL to query."
  echo "  --target:  The target number of batches."
  echo "  --timeout: The script timeout in seconds."
  exit 1
}

# Initialize variables.
enclave=""
rpc_url=""
target="10"
timeout="900" # 15 minutes.

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  --enclave)
    enclave="$2"
    shift 2
    ;;
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
    echo "Error: unknown argument: $key"
    usage
    ;;
  esac
done

# Check if the required argument is provided.
if [ -z "$enclave" ]; then
  echo "Error: enclave name is required."
  usage
fi

if [ -z "$rpc_url" ]; then
  echo "Error: rpc url is required."
  usage
fi

# Print script parameters for debug purposes.
echo "Running script with values:"
echo "- Enclave: $enclave"
echo "- RPC URL: $rpc_url"
echo "- Target: $target"
echo "- Timeout: $timeout"
echo

# Calculate the end time based on the current time and the specified timeout.
start_time=$(date +%s)
end_time=$((start_time + timeout))

# Main loop to monitor batch verification.
gas_price_factor=1
while true; do
  # Check if there are any stopped services.
  stopped_services="$(kurtosis enclave inspect "$enclave" | grep STOPPED)"
  if [[ -n "$stopped_services" ]]; then
    echo "It looks like there is at least one stopped service in the enclave... Something must have halted..."
    echo "$stopped_services"
    echo

    kurtosis enclave inspect "$enclave" --full-uuids | grep STOPPED | awk '{print $2 "--" $1}' \
      | while read -r container; do echo "Printing logs for $container"; docker logs --tail 50 "$container"; done
    exit 1
  fi

  # Query the number of batches from the RPC URL.
  batch_number="$(cast to-dec "$(cast rpc --rpc-url "$rpc_url" zkevm_batchNumber | sed 's/"//g')")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Latest Batch: $batch_number"

  # Check if the batches target has been reached.
  if ((batch_number > target)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Exiting... More than $target batches were created!"
    exit 0
  fi

  # Check if the timeout has been reached.
  current_time=$(date +%s)
  if ((current_time > end_time)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
    exit 1
  fi

  gas_price=$(cast gas-price --rpc-url "$rpc_url")
  gas_price=$(bc -l <<< "$gas_price * $gas_price_factor" | sed 's/\..*//')

  echo "Sending a transaction to increase the batch number..."
  cast send \
    --legacy \
    --timeout 30 \
    --gas-price "$gas_price" \
    --rpc-url "$rpc_url" \
    --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    --gas-limit 100000 \
    --create 0x6001617000526160006110005ff05b6109c45a111560245761600061100080833c600e565b50
  ret_code=$?
  if [[ $ret_code -eq 0 ]]; then
      gas_price_factor=1
  else
      gas_price_factor=$(bc -l <<< "$gas_price_factor * 1.5")
  fi

  echo "Waiting a few seconds before the next iteration..."
  echo
  sleep 10
done
