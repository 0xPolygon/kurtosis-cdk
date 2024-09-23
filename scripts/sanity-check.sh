#!/bin/bash

# Sanity checks to do
# - Log check
# - All contianers running
# - Matching values from rpc and sequencer
# - Matching values from rpc and data stream
# - Is this a validium or a rollup
# - Dac Committe Members
# - Batch verification gap

# Local
l1_rpc_url=$(kurtosis port print cdk-v1 el-1-geth-lighthouse rpc)
l2_rpc_url=$(kurtosis port print cdk-v1 cdk-erigon-sequencer-001 rpc)
rollup_manager_addr="0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2"
rollup_id=1

# Xavi
# l1_rpc_url=$(kurtosis port print erigon-18-4 el-1-geth-lighthouse rpc)
# l2_rpc_url=$(kurtosis port print erigon-18-4 sequencer001 sequencer8123)
# rollup_manager_addr="0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2"
# rollup_id=1

# BALI
# l1_rpc_url="https://rpc2.sepolia.org"
# l2_rpc_url="https://rpc.internal.zkevm-rpc.com"
# rollup_manager_addr="0xe2ef6215adc132df6913c8dd16487abf118d1764"
# rollup_id=1

# CARDONA
# l1_rpc_url="https://rpc2.sepolia.org"
# l2_rpc_url="https://rpc.cardona.zkevm-rpc.com"
# rollup_manager_addr="0x32d33D5137a7cFFb54c5Bf8371172bcEc5f310ff"
# rollup_id=1

sig_rollup_id_to_data='rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)'
sig_get_sequenced_batches='getRollupSequencedBatches(uint32,uint64)(bytes32,uint64,uint64)'
sig_get_stateroot='getRollupBatchNumToStateRoot(uint32,uint64)(bytes32)'

rollup_data_json=$(cast call -j --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_rollup_id_to_data" "$rollup_id")

rollup_contract=$(echo "$rollup_data_json" | jq -r '.[0]')
chain_id=$(echo "$rollup_data_json" | jq -r '.[1]')
verifier=$(echo "$rollup_data_json" | jq -r '.[2]')
fork_id=$(echo "$rollup_data_json" | jq -r '.[3]')
last_local_exit_root=$(echo "$rollup_data_json" | jq -r '.[4]')
last_batch_sequenced=$(echo "$rollup_data_json" | jq -r '.[5]')
last_verified_batch=$(echo "$rollup_data_json" | jq -r '.[6]')
last_pending_state=$(echo "$rollup_data_json" | jq -r '.[7]')
last_pending_state_consolidated=$(echo "$rollup_data_json" | jq -r '.[8]')
last_verified_batch_before_upgrade=$(echo "$rollup_data_json" | jq -r '.[9]')
rollup_type_id=$(echo "$rollup_data_json" | jq -r '.[10]')
rollup_compatibility_id=$(echo "$rollup_data_json" | jq -r '.[11]')

latest_batch_number=$(cast rpc --rpc-url "$l2_rpc_url" zkevm_batchNumber | jq -r '.')

echo "Rollup Contract:                     $rollup_contract"
echo "Chain ID:                            $chain_id"
echo "Verifier Address:                    $verifier"
echo "Fork ID:                             $fork_id"
echo "Last LER:                            $last_local_exit_root"
echo "Last Sequenced Batch:                $last_batch_sequenced"
echo "Last Verified Batch:                 $last_verified_batch"
echo "Last Pending State:                  $last_pending_state"
echo "Last Pending State Consolidated:     $last_pending_state_consolidated"
echo "Last Verified Batch Before Upgrade:  $last_verified_batch_before_upgrade"
echo "Rollup Type ID:                      $rollup_type_id"
echo "Rollup Compatibility ID:             $rollup_compatibility_id"

simple_batch_info=$(cast rpc --rpc-url "$l2_rpc_url" zkevm_getBatchByNumber "$latest_batch_number" | jq '.')
simple_simple_batch=$(echo "$simple_batch_info" | jq '.transactions = (.transactions | length) | .blocks = (.blocks | length) | del(.batchL2Data)')
echo "$simple_simple_batch" | jq '.'

virtual_batch_info=$(cast rpc --rpc-url "$l2_rpc_url" zkevm_getBatchByNumber "$(printf "0x%x" "$last_batch_sequenced")" | jq '.')
simple_virtual_batch=$(echo "$virtual_batch_info" | jq '.transactions = (.transactions | length) | .blocks = (.blocks | length) | del(.batchL2Data)')
echo "$simple_virtual_batch" | jq '.'

verified_batch_info=$(cast rpc --rpc-url "$l2_rpc_url" zkevm_getBatchByNumber "$(printf "0x%x" "$last_verified_batch")" | jq '.')
simple_verifed_batch=$(echo "$verified_batch_info" | jq '.transactions = (.transactions | length) | .blocks = (.blocks | length) | del(.batchL2Data)')
echo "$simple_verifed_batch" | jq '.'

sequenced_batch_data_json=$(cast call -j --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_get_sequenced_batches" "$rollup_id" "$last_batch_sequenced")
sequenced_batch_sr_json=$(cast call -j --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_get_stateroot" "$rollup_id" "$last_batch_sequenced")

seq_acc_input_hash=$(echo "$sequenced_batch_data_json" | jq -r '.[0]')
sequenced_timestamp=$(echo "$sequenced_batch_data_json" | jq -r '.[1]')
seq_previous_last_batch_sequenced=$(echo "$sequenced_batch_data_json" | jq -r '.[2]')
seq_state_root=$(echo "$sequenced_batch_sr_json" | jq -r '.[0]')

echo "Batch $last_batch_sequenced accInputHash:               $seq_acc_input_hash"
echo "Batch $last_batch_sequenced sequencedTimestamp:         $sequenced_timestamp"
echo "Batch $last_batch_sequenced previousLastBatchSequenced: $seq_previous_last_batch_sequenced"
echo "Batch $last_batch_sequenced stateRoot:                  $seq_state_root"

verified_batch_data_json=$(cast call -j --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_get_sequenced_batches" "$rollup_id" "$last_verified_batch")
verified_batch_sr_json=$(cast call -j --rpc-url "$l1_rpc_url" "$rollup_manager_addr" "$sig_get_stateroot" "$rollup_id" "$last_verified_batch")

verified_acc_input_hash=$(echo "$verified_batch_data_json" | jq -r '.[0]')
verified_timestamp=$(echo "$verified_batch_data_json" | jq -r '.[1]')
verif_previous_last_batch_sequenced=$(echo "$verified_batch_data_json" | jq -r '.[2]')
verif_state_root=$(echo "$verified_batch_sr_json" | jq -r '.[0]')

echo "Batch $last_verified_batch accInputHash:               $verified_acc_input_hash"
echo "Batch $last_verified_batch sequencedTimestamp:         $verified_timestamp"
echo "Batch $last_verified_batch previousLastBatchSequenced: $verif_previous_last_batch_sequenced"
echo "Batch $last_verified_batch stateRoot:                  $verif_state_root"


