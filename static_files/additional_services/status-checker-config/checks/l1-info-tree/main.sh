#!/usr/bin/env bash

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=static_files/additional_services/status-checker-config/checks/lib.sh
source "../lib.sh"

check_consensus rollup cdk_validium

# Ensure that no more than $last_n_events batches sequenced can be processed
# within the status-checker check interval.
last_n_events=10
rollup_contract=$(jq -r '.rollupAddress' /opt/zkevm/combined.json)
virtual_batch_number=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_virtualBatchNumber | jq -r | cast to-dec)

events=$(
  cast logs "SequenceBatches(uint64,bytes32)" \
    --rpc-url "$L1_RPC_URL" \
    --address "$rollup_contract" \
    --json | jq -r '.[] | .topics[1]' | tail -n "$last_n_events"
)

if [[ -z "$events" ]]; then
  exit 0
fi

# Iterate over the sequence batches events because sometimes the batch number is
# greater than the virtual batch.
while IFS= read -r hex; do
  batch_number=$(printf "%s\n" "$hex" | cast to-dec)

  if [[ "$batch_number" -gt "$virtual_batch_number" ]]; then
    continue
  fi

  vb_json=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_getBatchByNumber "$batch_number")
  tx_hash=$(echo "$vb_json" | jq -r '.sendSequencesTxHash')
  tx_json=$(cast tx --json --rpc-url "$L1_RPC_URL" "$tx_hash")
  input_data=$(echo "$tx_json" | jq -r '.input')
  batch_l2_data=$(echo "$vb_json" | jq -r '.batchL2Data')
  echo "$batch_l2_data" > batch_l2_data.txt

  if is_consensus rollup; then
    l1_info_tree_leaf_count=$(
      cast cdd --json \
        "sequenceBatches((bytes,bytes32,uint64,bytes32)[],uint32,uint64,bytes32,address)" \
        "$input_data" \
        | jq -r '.[1]'
    )
  elif is_consensus cdk_validium; then
    l1_info_tree_leaf_count=$(
      cast cdd --json \
        "sequenceBatchesValidium((bytes32,bytes32,uint64,bytes32)[],uint32,uint64,bytes32,address,bytes)" \
        "$input_data" \
        | jq -r '.[1]'
    )
  fi

  # The Go script decodes the batch L2 data into JSON. If using the offline
  # status-checker image, then the decode-batch-l2-data binary will be built;
  # otherwise, just build the go script on the fly.
  if command -v decode-batch-l2-data &> /dev/null; then
    indexes=$(decode-batch-l2-data batch_l2_data.txt | jq -r '.Blocks[] | .IndexL1InfoTree')
  else
    indexes=$(go run main.go batch_l2_data.txt | jq -r '.Blocks[] | .IndexL1InfoTree')
  fi

  while IFS= read -r index; do
    if (( index >= "$l1_info_tree_leaf_count" )); then
      echo "ERROR: IndexL1InfoTree is >= L1InfoTreeLeafCount index=$index count=$l1_info_tree_leaf_count batch_number=$batch_number"
      exit 1
    fi
  done <<< "$indexes"

done <<< "$events" 
