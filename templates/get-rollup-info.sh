#!/bin/bash

# This script retrieves all the rollup data using the rollup manager address and the chain id.
rpc_url="{{.rpc_url}}"
zkevm_rollup_manager_address="{{.zkevm_rollup_manager_address}}"
zkevm_rollup_chain_id="{{.zkevm_rollup_chain_id}}"

rollup_id="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "chainIDToRollupID(uint64)(uint32)" "$zkevm_rollup_chain_id")"
zkevm_rollup_address="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)" "$rollup_id" | sed -n "1p")"
zkevm_bridge_address="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "bridgeAddress()(address)")"
zkevm_global_exit_root_address="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "globalExitRootManager()(address)")"
pol_token_address="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "pol()(address)")"
echo '{' \
  \"polygonZkEVMBridgeAddress\":\""$zkevm_bridge_address"\", \
  \"rollupAddress\":\""$zkevm_rollup_address"\", \
  \"polygonRollupManagerAddress\":\""$zkevm_rollup_manager_address"\", \
  \"deploymentRollupManagerBlockNumber\":\""{{.zkevm_rollup_manager_block_number}}"\", \
  \"polygonZkEVMGlobalExitRootAddress\":\""$zkevm_global_exit_root_address"\", \
  \"polygonZkEVMGlobalExitRootL2Address\":\""{{.zkevm_global_exit_root_l2_address}}"\", \
  \"polygonDataCommitteeAddress\":\""{{.polygon_data_committee_address}}"\", \
  \"admin\":\""{{.zkevm_admin_address}}"\", \
  \"polTokenAddress\":\""$pol_token_address"\" \
'}' | jq > /opt/zkevm/combined.json
