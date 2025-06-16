#!/usr/bin/env bash

# shellcheck source=static_files/additional_services/status-checker-config/checks/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

check_consensus rollup cdk_validium

threshold=5
methods=("zkevm_batchNumber" "zkevm_verifiedBatchNumber" "zkevm_virtualBatchNumber")
error=0

for rpc_method in "${methods[@]}"; do
  seq_bn=$(cast to-dec "$(cast rpc --rpc-url "$SEQUENCER_RPC_URL" "$rpc_method" | sed 's/\"//g')")
  rpc_bn=$(cast to-dec "$(cast rpc --rpc-url "$L2_RPC_URL" "$rpc_method" | sed 's/\"//g')")

  delta=$(( seq_bn > rpc_bn ? seq_bn - rpc_bn : rpc_bn - seq_bn ))
  if (( delta > threshold )); then
    echo "ERROR: $rpc_method is out of sync, sequencer=$seq_bn rpc=$rpc_bn"
    error=1
  fi
done

exit "$error"
