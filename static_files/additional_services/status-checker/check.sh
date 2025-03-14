#!/bin/bash

# This scripts monitors the verification progress of zkEVM batches.
# It queries a specified RPC URL and tracks the number of verified batches.

gas_price_factor=1
while true; do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ZkEVM Batch No."
  batch_number="$(cast to-dec "$(cast rpc --rpc-url {{.rpc_url}} zkevm_batchNumber | sed 's/"//g')")"
  echo "Trusted: ${batch_number}"
  virtual_batch_number="$(cast to-dec "$(cast rpc --rpc-url {{.rpc_url}} zkevm_virtualBatchNumber | sed 's/"//g')")"
  echo "Virtual: ${virtual_batch_number}"
  verified_batch_number="$(cast to-dec "$(cast rpc --rpc-url {{.rpc_url}} zkevm_verifiedBatchNumber | sed 's/"//g')")"
  echo "Verified: ${verified_batch_number}"

  # Send transactions to increase the number of batches.
  gas_price=$(cast gas-price --rpc-url {{.rpc_url}})
  gas_price=$(bc -l <<<"${gas_price} * ${gas_price_factor}" | sed 's/\..*//')
  cast send \
    --legacy \
    --timeout 30 \
    --gas-price "${gas_price}" \
    --rpc-url {{.rpc_url}} \
    --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
    --gas-limit 100000 \
    --create 0x6001617000526160006110005ff05b6109c45a111560245761600061100080833c600e565b50
  ret_code=$?
  if [[ "${ret_code}" -eq 0 ]]; then
    gas_price_factor=1
  else
    gas_price_factor=$(bc -l <<<"${gas_price_factor} * 1.5")
  fi

  # Waiting a few seconds before the next iteration.
  sleep 10
done
