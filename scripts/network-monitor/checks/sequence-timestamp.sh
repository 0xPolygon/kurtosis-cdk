#!/bin/bash

set -euo pipefail

l1_rpc_url="http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)"
l2_rpc_url="$(kurtosis port print cdk cdk-erigon-sequencer-001 rpc)"

to_hex() {
  perl -nle 'print hex $_'
}

virtual_batch_number=$(cast rpc --rpc-url "$l2_rpc_url" zkevm_virtualBatchNumber | jq -r | to_hex)

contract="0x28eb6e90A1d4C8ba008d89d13482EdeFFf595461"
events=$(cast logs "SequenceBatches(uint64,bytes32)" \
  --rpc-url "$l1_rpc_url" \
  --address "$contract" \
  --json | jq -r '.[] | .topics[1]')

while IFS= read -r hex; do
  batch_number=$(printf "%s\n" "$hex" | to_hex)

  if [ "$batch_number" -gt "$virtual_batch_number" ]; then
    continue
  fi

  vb_json=$(cast rpc --rpc-url "$l2_rpc_url" zkevm_getBatchByNumber "$batch_number")
  block_hash=$(echo "$vb_json" | jq -r '.blocks[-1]')
  tx_hash=$(echo "$vb_json" | jq -r '.sendSequencesTxHash')
  batch_ts=$(echo "$vb_json" | jq -r '.timestamp' | to_hex)

  vb_block_json=$(cast block --json --rpc-url "$l2_rpc_url" "$block_hash")
  block_ts=$(echo "$vb_block_json" | jq -r '.timestamp' | to_hex)

  tx_json=$(cast tx --json --rpc-url "$l1_rpc_url" "$tx_hash")
  input_data=$(echo "$tx_json" | jq -r '.input')

  seq_ts=$(cast cdd --json 'sequenceBatchesValidium((bytes32,bytes32,uint64,bytes32)[], uint32, uint64, bytes32, address, bytes)' "$input_data" | jq -r '.[2]')

  if [ "$seq_ts" -ne "$batch_ts" ] || [ "$batch_ts" -ne "$block_ts" ]; then
    exit 1
  fi
done <<< "$events" | tail -n 100

exit 0
