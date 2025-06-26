#!/usr/bin/env bash

# shellcheck source=static_files/additional_services/status-checker-config/checks/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

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

miner=$(cast block --rpc-url "$L2_RPC_URL" --json | jq -r '.miner')

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

  if is_consensus rollup; then
    l2_coinbase=$(
      cast cdd --json \
        "sequenceBatches((bytes,bytes32,uint64,bytes32)[],uint32,uint64,bytes32,address)" \
        "$input_data" \
        | jq -r '.[4]'
    )
  elif is_consensus cdk_validium; then
    l2_coinbase=$(
      cast cdd --json \
        "sequenceBatchesValidium((bytes32,bytes32,uint64,bytes32)[],uint32,uint64,bytes32,address,bytes)" \
        "$input_data" \
        | jq -r '.[4]'
    )
  fi

  l2_coinbase=${l2_coinbase,,}
  if [[ "$miner" != "$l2_coinbase" ]]; then
    echo "ERROR: L2 coinbase mismatch miner=$miner l2_coinbase=$l2_coinbase"
    exit 1
  fi
done <<< "$events" 
