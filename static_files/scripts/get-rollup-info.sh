#!/bin/bash

# This script retrieves all the rollup data using the rollup manager address and the chain id.
rpc_url="{{.rpc_url}}"
rollup_manager_address="{{.rollup_manager_address}}"
zkevm_rollup_chain_id="{{.zkevm_rollup_chain_id}}"

rollup_id="$(cast call --rpc-url "$rpc_url" "$rollup_manager_address" "chainIDToRollupID(uint64)(uint32)" "$zkevm_rollup_chain_id")"
rollup_address="$(cast call --rpc-url "$rpc_url" "$rollup_manager_address" "rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)" "$rollup_id" | sed -n "1p")"
l1_bridge_address="$(cast call --rpc-url "$rpc_url" "$rollup_manager_address" "bridgeAddress()(address)")"
l1_ger_address="$(cast call --rpc-url "$rpc_url" "$rollup_manager_address" "globalExitRootManager()(address)")"
pol_token_address="$(cast call --rpc-url "$rpc_url" "$rollup_manager_address" "pol()(address)")"
echo '{' \
  \"AgglayerBridge\":\""$l1_bridge_address"\", \
  \"rollupAddress\":\""$rollup_address"\", \
  \"AgglayerManager\":\""$rollup_manager_address"\", \
  \"deploymentRollupManagerBlockNumber\":\""{{.rollup_manager_block_number}}"\", \
  \"AgglayerGER\":\""$l1_ger_address"\", \
  \"LegacyAgglayerGERL2\":\""{{.l2_ger_address}}"\", \
  \"polygonDataCommitteeAddress\":\""{{.polygon_data_committee_address}}"\", \
  \"admin\":\""{{.admin_address}}"\", \
  \"polTokenAddress\":\""$pol_token_address"\" \
'}' | jq > "{{.output_dir}}"/combined.json
