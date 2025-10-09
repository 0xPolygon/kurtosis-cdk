#!/usr/bin/env bash

input_dir="/opt/input"

# Create New Rollup Step
pushd /opt/zkevm-contracts || exit 1

# Requirement to correctly configure contracts deployer
export DEPLOYER_PRIVATE_KEY="{{.zkevm_l2_admin_private_key}}"

ts=$(date +%s)

# Extract the rollup manager address from the JSON file. .zkevm_rollup_manager_address is not available at the time of importing this script.
# So a manual extraction of polygonRollupManagerAddress is done here.
# Even with multiple op stack deployments, the rollup manager address can be retrieved from combined{{.deployment_suffix}}.json because it must be constant.
rollup_manager_addr="$(jq -r '.polygonRollupManagerAddress' "/opt/zkevm/combined{{.deployment_suffix}}.json")"

# Replace rollupManagerAddress with the extracted address
jq --arg rum "$rollup_manager_addr" '.rollupManagerAddress = $rum' "$input_dir"/create_new_rollup.json > "${input_dir}/create_new_rollup${ts}.json"
cp "${input_dir}/create_new_rollup${ts}.json" "$input_dir"/create_new_rollup.json

# Replace polygonRollupManagerAddress with the extracted address
jq --arg rum "$rollup_manager_addr" '.polygonRollupManagerAddress = $rum' "/opt/contract-deploy/add_rollup_type.json" > "/opt/contract-deploy/add_rollup_type${ts}.json"
cp "/opt/contract-deploy/add_rollup_type${ts}.json" "/opt/contract-deploy/add_rollup_type.json"

# This will require genesis.json and create_new_rollup.json to be correctly filled. We are using a pre-defined template for these.
# The script and example files exist under https://github.com/0xPolygonHermez/zkevm-contracts/tree/v9.0.0-rc.5-pp/tools/createNewRollup
# The templates being used here: create_new_rollup.json and genesis.json were directly referenced from the above source.

cp /opt/contract-deploy/add_rollup_type.json   /opt/zkevm-contracts/tools/addRollupType/add_rollup_type.json
cp "$input_dir"/create_new_rollup.json /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup.json

# 2025-04-03 - These are removed for now because the genesis is created later. I'm using the genesis that's created by 1_createGenesis - hopefully that's right.
# cp /opt/contract-deploy/sovereign-genesis.json /opt/zkevm-contracts/tools/addRollupType/genesis.json
# cp /opt/contract-deploy/sovereign-genesis.json /opt/zkevm-contracts/tools/createNewRollup/genesis.json
cp /opt/zkevm-contracts/deployment/v2/genesis.json  /opt/zkevm-contracts/tools/addRollupType/genesis.json
cp /opt/zkevm-contracts/deployment/v2/genesis.json  /opt/zkevm-contracts/tools/createNewRollup/genesis.json

cp /opt/zkevm/combined.json /opt/zkevm-contracts/deployment/v2/deploy_output.json

deployOPSuccinct="{{ .deploy_op_succinct }}"
if [[ $deployOPSuccinct == true ]]; then
rm /opt/zkevm-contracts/tools/addRollupType/add_rollup_type_output-*.json
npx hardhat run tools/addRollupType/addRollupType.ts --network localhost 2>&1 | tee 06_create_rollup_type.out
cp /opt/zkevm-contracts/tools/addRollupType/add_rollup_type_output-*.json /opt/zkevm/add_rollup_type_output.json
rollup_type_id=$(jq -r '.rollupTypeID' /opt/zkevm/add_rollup_type_output.json)
jq --arg rtid "$rollup_type_id"  '.rollupTypeId = $rtid' /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup.json > /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup.json.tmp
mv /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup.json.tmp /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup.json

rm /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup_output_*.json
npx hardhat run ./tools/createNewRollup/createNewRollup.ts --network localhost 2>&1 | tee 07_create_sovereign_rollup.out
cp /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup_output_*.json /opt/zkevm/create_rollup_output.json
else
# shellcheck disable=SC2050
if [[ "{{ .zkevm_rollup_id }}" != "1" ]]; then
sed -i '/await aggLayerGateway\.addDefaultAggchainVKey(/,/);/s/^/\/\/ /' /opt/zkevm-contracts/deployment/v2/4_createRollup.ts
fi
# In the case for PP deployments without OP-Succinct, use the 4_createRollup.ts script instead of the createNewRollup.ts tool.
cp "$input_dir"/create_new_rollup.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee 05_create_sovereign_rollup.out
fi

# Save Rollup Information to a file.
cast call --json --rpc-url "{{.l1_rpc_url}}" "$rollup_manager_addr" 'rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' "{{.zkevm_rollup_id}}" | jq '{"sovereignRollupContract": .[0], "rollupChainID": .[1], "verifier": .[2], "forkID": .[3], "lastLocalExitRoot": .[4], "lastBatchSequenced": .[5], "lastVerifiedBatch": .[6], "_legacyLastPendingState": .[7], "_legacyLastPendingStateConsolidated": .[8], "lastVerifiedBatchBeforeUpgrade": .[9], "rollupTypeID": .[10], "rollupVerifierType": .[11]}' > /opt/zkevm-contracts/sovereign-rollup-out.json

