#!/usr/bin/env bash

CONSENSUS_CONTRACT_TYPE=cdk_validium
L1_RPC_URL="http://$(kurtosis port print cdk el-1-geth-lighthouse rpc)"
L2_RPC_URL="$(kurtosis port print cdk cdk-erigon-sequencer-001 rpc)"

# CONSENSUS_CONTRACT_TYPE=rollup
# L1_RPC_URL="https://ethereum.publicnode.com"
# L2_RPC_URL="https://zkevm-rpc.com"

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=static_files/additional_services/status-checker-config/checks/lib.sh
source "../lib.sh"

check_consensus rollup cdk_validium

# Ensure that no more than $last_n_events batches sequenced can be processed
# within the status-checker check interval.
last_n_events=10
rollup_contract="0x414e9E227e4b589aF92200508aF5399576530E4e"
# rollup_contract="0x519E42c24163192Dca44CD3fBDCEBF6be9130987" # zkEVM mainnet rollup
# rollup_contract=$(jq -r '.rollupAddress' /opt/zkevm/combined.json)
virtual_batch_number=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_virtualBatchNumber | jq -r | cast to-dec)

# latest_block_number=$(cast block-number --rpc-url $L1_RPC_URL) 
# from_block=$((latest_block_number - 10000)) 
# echo "latest_block: $latest_block_number"
# echo "from_block: $from_block"

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

  if [[ "$batch_number" -gt "$virtual_batch_number" ]]; then
    continue
  fi

  vb_json=$(cast rpc --rpc-url "$L2_RPC_URL" zkevm_getBatchByNumber "$batch_number")
  tx_hash=$(echo "$vb_json" | jq -r '.sendSequencesTxHash')
  tx_json=$(cast tx --json --rpc-url "$L1_RPC_URL" "$tx_hash")
  input_data=$(echo "$tx_json" | jq -r '.input')
  batch_l2_data=$(echo $vb_json | jq -r '.batchL2Data')

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

  go run main.go "$batch_l2_data" \
    | jq -e --argjson v "$l1_info_tree_leaf_count" 'all(.Blocks[]; .IndexL1InfoTree < $v)' 

done <<< "$events" 
