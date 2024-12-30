#!/bin/bash

# This script monitors the finality of OP rollup blocks.
# TODO: Once we migrate the OP rollup into a type 1 zkEVM rollup, we'll be able to monitor the
# verification of those blocks.

# Function to display usage information.
usage() {
  echo "Usage: $0 --enclave <ENCLAVE> --rpc-url <URL> --target <TARGET> --timeout <TIMEOUT>"
  echo "  --enclave: The name of the Kurtosis enclave."
  echo "  --cl-rpc-url: The consensus layer RPC URL to query."
  echo "  --target:  The target number of finalized blocks."
  echo "  --timeout: The script timeout in seconds."
  exit 1
}

# Initialize variables.
enclave=""
cl_rpc_url=""
target="50"
timeout="900" # 15 minutes.

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  --enclave)
    enclave="$2"
    shift 2
    ;;
  --cl-rpc-url)
    cl_rpc_url="$2"
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

if [ -z "$cl_rpc_url" ]; then
  echo "Error: cl rpc url is required."
  usage
fi

# Print script parameters for debug purposes.
echo "Running script with values:"
echo "- Enclave: $enclave"
echo "- CL RPC URL: $cl_rpc_url"
echo "- Target: $target"
echo "- Timeout: $timeout"
echo

# Calculate the end time based on the current time and the specified timeout.
start_time=$(date +%s)
end_time=$((start_time + timeout))

# Main loop to monitor block finalization.
while true; do
  # Check if there are any stopped services.
  stopped_services="$(kurtosis enclave inspect "$enclave" | grep STOPPED)"
  if [[ -n "$stopped_services" ]]; then
    echo "It looks like there is at least one stopped service in the enclave... Something must have halted..."
    echo "$stopped_services"
    echo

    kurtosis enclave inspect "$enclave" --full-uuids | grep STOPPED | awk '{print $2 "--" $1}' |
      while read -r container; do
        echo "Printing logs for $container"
        docker logs --tail 50 "$container"
      done
    exit 1
  fi

  # Query the number of finalized blocks from the CL RPC URL.
  op_rollup_sync_status="$(cast rpc --rpc-url "$cl_rpc_url" optimism_syncStatus)"
  unsafe_l2_block_number="$(jq '.unsafe_l2.number' <<<"$op_rollup_sync_status")"
  safe_l2_block_number="$(jq '.safe_l2.number' <<<"$op_rollup_sync_status")"
  finalized_l2_block_number="$(jq '.finalized_l2.number' <<<"$op_rollup_sync_status")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Unsafe: $unsafe_l2_block_number, Safe: $safe_l2_block_number, Finalized: $finalized_l2_block_number"

  # Check if the finalized block target has been reached.
  if ((finalized_l2_block_number > target)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Exiting... More than $target L2 blocks were finalized!"
    exit 0
  fi

  # Check if the timeout has been reached.
  current_time=$(date +%s)
  if ((current_time > end_time)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
    exit 1
  fi

  echo "Waiting a few seconds before the next iteration..."
  echo
  sleep 10
done
