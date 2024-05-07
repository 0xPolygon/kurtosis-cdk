#!/bin/bash

# This script retrieves all the rollup data using the rollup manager address and the chain id.
rpc_url="$1"
zkevm_rollup_manager_address="$2"
zkevm_rollup_chain_id="$3"

# Check if all three arguments are provided.
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <rpc_url> <zkevm_rollup_manager_address> <zkevm_rollup_chain_id>"
  exit 1
fi

rollup_id="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "chainIDToRollupID(uint64)(uint32)" "$zkevm_rollup_chain_id")"
zkevm_rollup_address="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)" "$rollup_id" | sed -n "1p")"
zkevm_bridge_address="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "bridgeAddress()(address)")"
zkevm_global_exit_root_address="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "globalExitRootManager()(address)")"
pol_token_address="$(cast call --rpc-url "$rpc_url" "$zkevm_rollup_manager_address" "pol()(address)")"
echo \{\"zkevm_bridge_address\":\"$zkevm_bridge_address\", \"zkevm_rollup_address\":\"$zkevm_rollup_address\", \"zkevm_rollup_manager_address\":\"$zkevm_rollup_manager_address\", \"zkevm_global_exit_root_address\":\"$zkevm_global_exit_root_address\", \"pol_token_address\":\"$pol_token_address\"\}
