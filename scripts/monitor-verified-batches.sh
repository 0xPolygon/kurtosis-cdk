#!/bin/bash

# This script monitors the verification progress of zkEVM batches.

# Define default parameters.
RPC_URL="$(kurtosis port print cdk-v1 zkevm-node-rpc-001 http-rpc)"
TARGET=20
TIMEOUT=900 # 15min

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --rpc-url   The url of the RPC service to query (default: zkevm-node-rpc-001's rpc url)"
  echo "  --target    The number of batches to be verified (default: 20)"
  echo "  --timeout   The script timeout in seconds (default: 15min)"
  echo "  -h, --help  Display this help message"
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --rpc-url)
      RPC_URL="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    esac
  done
}

start_time=$(date +%s)
end_time=$((start_time + TIMEOUT))

while true; do
  verified_batches="$(cast to-dec "$(cast rpc --rpc-url "$RPC_URL" zkevm_verifiedBatchNumber | sed 's/"//g')")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Verified Batches: $verified_batches"

  # The aim is to take up some space in the batch, so that the number of batches actually increases during the test.
  cast send \
    --legacy \
    --rpc-url "$RPC_URL" \
    --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    --gas-limit 643528 \
    --create 0x600160015B810190630000000456 \
    >/dev/null 2>&1

  current_time=$(date +%s)
  if ((current_time > end_time)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Exiting... Timeout reached!"
    exit 1
  fi

  if ((verified_batches > TARGET)); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Exiting... $verified_batches batches were verified!"
    exit 0
  fi

  sleep 10
done
