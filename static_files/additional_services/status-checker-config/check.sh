#!/bin/bash

# This scripts monitors the verification progress of zkEVM batches.
# It queries a specified RPC URL and tracks the number of verified batches.

previous_trusted_bn=0
previous_trusted_bn_idle_counter=0
previous_virtual_bn=0
previous_virtual_bn_idle_counter=0
previous_verified_bn=0
previous_verified_bn_idle_counter=0

while true; do
  # Monitor batches.
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ZkEVM Batch No."

  trusted_bn="$(cast to-dec "$(cast rpc --rpc-url "{{.rpc_url}}" zkevm_batchNumber | sed 's/"//g')")"
  echo "Trusted: ${trusted_bn}"
  if [[ "${trusted_bn}" -gt "${previous_trusted_bn}" ]]; then
    previous_trusted_bn="${trusted_bn}"
    previous_trusted_bn_idle_counter=0
  else
    previous_trusted_bn_idle_counter=$((previous_trusted_bn_idle_counter + 1))
    if [[ "${previous_trusted_bn_idle_counter}" -ge 12 ]]; then
      echo "ERROR: Trusted batch number is stuck."
    fi
  fi

  virtual_bn="$(cast to-dec "$(cast rpc --rpc-url "{{.rpc_url}}" zkevm_virtualBatchNumber | sed 's/"//g')")"
  echo "Virtual: ${virtual_bn}"
  if [[ "${virtual_bn}" -gt "${previous_virtual_bn}" ]]; then
    previous_virtual_bn="${virtual_bn}"
    previous_virtual_bn_idle_counter=0
  else
    previous_virtual_bn_idle_counter=$((previous_virtual_bn_idle_counter + 1))
    if [[ "${previous_virtual_bn_idle_counter}" -ge 12 ]]; then
      echo "ERROR: Virtual batch number is stuck."
    fi
  fi

  verified_bn="$(cast to-dec "$(cast rpc --rpc-url "{{.rpc_url}}" zkevm_verifiedBatchNumber | sed 's/"//g')")"
  echo "Verified: ${verified_bn}"
  if [[ "${verified_bn}" -gt "${previous_verified_bn}" ]]; then
    previous_verified_bn="${verified_bn}"
    previous_verified_bn_idle_counter=0
  else
    previous_verified_bn_idle_counter=$((previous_verified_bn_idle_counter + 1))
    if [[ "${previous_verified_bn_idle_counter}" -ge 12 ]]; then
      echo "ERROR: Verified batch number is stuck."
    fi
  fi

  sleep 10
done
