#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

set -euo pipefail

if check_consensus rollup cdk_validium; then
  exit 0
fi

sig_rollup_id_to_data='rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)'
rollup_manager_addr="0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2"
rollup_id=1
rollup_data_json=$(cast call --json --rpc-url "$L1_RPC_URL" "$rollup_manager_addr" "$sig_rollup_id_to_data" "$rollup_id")
rollup_contract=$(echo "$rollup_data_json" | jq -r '.[0]')

# Ensure that no more than $last_n_events batches sequenced can be processed
# within the status-checker check interval.
last_n_events=10

virtual_batch_number=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_virtualBatchNumber | jq -r | cast to-dec)

events=$(
  cast logs "SequenceBatches(uint64,bytes32)" \
    --rpc-url "$L1_RPC_URL" \
    --address "$rollup_contract" \
    --json | jq -r '.[] | .topics[1]' | tail -n "$last_n_events"
)

# Iterate over the sequence batches events because sometimes the batch number is
# is greater than the virtual batch.
while IFS= read -r hex; do
  batch_number=$(printf "%s\n" "$hex" | cast to-dec)

  if [ "$batch_number" -gt "$virtual_batch_number" ]; then
    continue
  fi

  vb_json=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_getBatchByNumber "$batch_number")
  block_hash=$(echo "$vb_json" | jq -r '.blocks[-1]')
  tx_hash=$(echo "$vb_json" | jq -r '.sendSequencesTxHash')
  batch_ts=$(echo "$vb_json" | jq -r '.timestamp' | cast to-dec)

  vb_block_json=$(cast block --json --rpc-url "$L2_RPC_URL" "$block_hash")
  block_ts=$(echo "$vb_block_json" | jq -r '.timestamp' | cast to-dec)

  tx_json=$(cast tx --json --rpc-url "$L1_RPC_URL" "$tx_hash")
  input_data=$(echo "$tx_json" | jq -r '.input')

  if [[ "$CONSENSUS_CONTRACT_TYPE" == "rollup" ]]; then
    seq_ts=$(
      cast cdd --json \
        "sequenceBatches((bytes,bytes32,uint64,bytes32)[],uint32,uint64,bytes32,address)" \
        "$input_data" \
        | jq -r '.[2]'
    )
  elif [[ "$CONSENSUS_CONTRACT_TYPE" == "cdk_validium" ]]; then
    seq_ts=$(
      cast cdd --json \
        "sequenceBatchesValidium((bytes32,bytes32,uint64,bytes32)[],uint32,uint64,bytes32,address,bytes)" \
        "$input_data" \
        | jq -r '.[2]'
    )
  fi

  if [ "$seq_ts" -ne "$batch_ts" ] || [ "$batch_ts" -ne "$block_ts" ]; then
    echo "ERROR: batch=$batch_number seq_ts=$seq_ts batch_ts=$batch_ts block_ts=$block_ts"
    exit 1
  fi
done <<< "$events" 
