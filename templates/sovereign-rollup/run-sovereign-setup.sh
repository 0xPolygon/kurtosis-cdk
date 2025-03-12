#!/bin/bash

# Fund L1 OP addresses.
IFS=';' read -ra addresses <<<"${L1_OP_ADDRESSES}"
private_key=$(cast wallet private-key --mnemonic "{{.l1_preallocated_mnemonic}}")
for address in "${addresses[@]}"; do
    echo "Funding ${address}"
    cast send \
        --private-key "$private_key" \
        --rpc-url "{{.l1_rpc_url}}" \
        --value "{{.l2_funding_amount}}" \
        "${address}"
done

# Create New Rollup Step
cd /opt/zkevm-contracts || exit

# Extract the rollup manager address from the JSON file. .zkevm_rollup_manager_address is not available at the time of importing this script.
# So a manual extraction of polygonRollupManagerAddress is done here.
# Even with multiple op stack deployments, the rollup manager address can be retrieved from combined{{.deployment_suffix}}.json because it must be constant.
rollup_manager_addr="$(jq -r '.polygonRollupManagerAddress' "/opt/zkevm/combined{{.deployment_suffix}}.json")"

# Replace rollupManagerAddress with the extracted address
sed -i "s|\"rollupManagerAddress\": \".*\"|\"rollupManagerAddress\":\"$rollup_manager_addr\"|" /opt/contract-deploy/create_new_rollup.json

# Replace polygonRollupManagerAddress with the extracted address
sed -i "s|\"polygonRollupManagerAddress\": \".*\"|\"polygonRollupManagerAddress\":\"$rollup_manager_addr\"|" /opt/contract-deploy/add_rollup_type.json

# This will require genesis.json and create_new_rollup.json to be correctly filled. We are using a pre-defined template for these.
# The script and example files exist under https://github.com/0xPolygonHermez/zkevm-contracts/tree/v9.0.0-rc.5-pp/tools/createNewRollup
# The templates being used here: create_new_rollup.json and genesis.json were directly referenced from the above source.
rollupTypeID="{{ .zkevm_rollup_id }}"
if [[ "$rollupTypeID" -eq 1 ]]; then
    # For the first rollup, we need use https://github.com/0xPolygonHermez/zkevm-contracts/blob/v9.0.0-rc.5-pp/deployment/v2/4_createRollup.ts
    echo "rollupID is 1. Running 4_createRollup.ts script"
    cp /opt/contract-deploy/create_new_rollup.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
    npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee 05_create_sovereign_rollup.out
else
    # The below method relies on https://github.com/0xPolygonHermez/zkevm-contracts/blob/v9.0.0-rc.5-pp/tools/createNewRollup/createNewRollup.ts
    # cp /opt/contract-deploy/create_new_rollup.json /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup.json
    # cp /opt/contract-deploy/sovereign-genesis.json /opt/zkevm-contracts/tools/createNewRollup/genesis.json
    # npx hardhat run ./tools/createNewRollup/createNewRollup.ts --network localhost 2>&1 | tee 06_create_sovereign_rollup.out

    # The below method relies on https://github.com/0xPolygonHermez/zkevm-contracts/blob/v9.0.0-rc.5-pp/deployment/v2/4_createRollup.ts
    cp /opt/contract-deploy/create_new_rollup.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
    npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee 05_create_sovereign_rollup.out
fi

# Save Rollup Information to a file.
cast call --json --rpc-url "{{.l1_rpc_url}}" "$rollup_manager_addr" 'rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' "{{.zkevm_rollup_id}}" | jq '{"sovereignRollupContract": .[0], "rollupChainID": .[1], "verifier": .[2], "forkID": .[3], "lastLocalExitRoot": .[4], "lastBatchSequenced": .[5], "lastVerifiedBatch": .[6], "_legacyLastPendingState": .[7], "_legacyLastPendingStateConsolidated": .[8], "lastVerifiedBatchBeforeUpgrade": .[9], "rollupTypeID": .[10], "rollupVerifierType": .[11]}' >/opt/zkevm-contracts/sovereign-rollup-out.json

# These are some accounts that we want to fund for operations for running claims.
bridge_admin_addr="{{.zkevm_l2_sovereignadmin_address}}"
bridge_admin_private_key="{{.zkevm_l2_sovereignadmin_private_key}}"
aggoracle_addr="{{.zkevm_l2_aggoracle_address}}"
# aggoracle_private_key="{{.zkevm_l2_aggoracle_private_key}}"
claimtx_addr="{{.zkevm_l2_claimtx_address}}"
# claimtx_private_key="{{.zkevm_l2_claimtx_private_key}}"

rpc_url="{{.op_el_rpc_url}}"
# This is the default prefunded account for the OP Network
private_key=$(cast wallet private-key --mnemonic 'test test test test test test test test test test test junk')

cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $bridge_admin_addr
cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $aggoracle_addr
cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $claimtx_addr

# Contract Deployment Step
cd /opt/zkevm-contracts || exit

echo "[profile.default]
src = 'contracts'
out = 'out'
libs = ['node_modules']" >foundry.toml

echo "Building contracts with forge build"
forge build contracts/v2/sovereignChains/BridgeL2SovereignChain.sol contracts/v2/sovereignChains/GlobalExitRootManagerL2SovereignChain.sol
bridge_impl_nonce=$(cast nonce --rpc-url $rpc_url $bridge_admin_addr)
bridge_impl_addr=$(cast compute-address --nonce "$bridge_impl_nonce" $bridge_admin_addr | sed 's/.*: //')
ger_impl_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 1)) $bridge_admin_addr | sed 's/.*: //')
ger_proxy_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 2)) $bridge_admin_addr | sed 's/.*: //')
bridge_proxy_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 3)) $bridge_admin_addr | sed 's/.*: //')

# This is one way to prefund the bridge. It can also be done with a deposit to some unclaimable network. This step is important and needs to be discussed
cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" "$bridge_proxy_addr"
forge create --legacy --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key BridgeL2SovereignChain
forge create --legacy --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key GlobalExitRootManagerL2SovereignChain --constructor-args "$bridge_proxy_addr"
calldata=$(cast calldata 'initialize(address _globalExitRootUpdater, address _globalExitRootRemover)' $aggoracle_addr $aggoracle_addr)
forge create --legacy --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key TransparentUpgradeableProxy --constructor-args "$ger_impl_addr" $bridge_admin_addr "$calldata"

initNetworkID="{{.zkevm_rollup_id}}"
initGasTokenAddress=$(cast az)
initGasTokenNetwork=0
initGlobalExitRootManager=$ger_proxy_addr
initPolygonRollupManager=$(cast az)
initGasTokenMetadata=0x
initBridgeManager=$bridge_admin_addr
initSovereignWETHAddress=$(cast az)
initSovereignWETHAddressIsNotMintable=false

calldata=$(cast calldata 'function initialize(uint32 _networkID, address _gasTokenAddress, uint32 _gasTokenNetwork, address _globalExitRootManager, address _polygonRollupManager, bytes _gasTokenMetadata, address _bridgeManager, address _sovereignWETHAddress, bool _sovereignWETHAddressIsNotMintable)' $initNetworkID "$initGasTokenAddress" $initGasTokenNetwork "$initGlobalExitRootManager" "$initPolygonRollupManager" $initGasTokenMetadata $initBridgeManager "$initSovereignWETHAddress" $initSovereignWETHAddressIsNotMintable)
forge create --legacy --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key TransparentUpgradeableProxy --constructor-args "$bridge_impl_addr" $bridge_admin_addr "$calldata"

# Save the contract addresses to the sovereign-rollup-out.json file
jq --arg bridge_impl_addr "$bridge_impl_addr" '. += {"bridge_impl_addr": $bridge_impl_addr}' /opt/zkevm-contracts/sovereign-rollup-out.json >/opt/zkevm-contracts/sovereign-rollup-out.json.temp && mv /opt/zkevm-contracts/sovereign-rollup-out.json.temp /opt/zkevm-contracts/sovereign-rollup-out.json
jq --arg ger_impl_addr "$ger_impl_addr" '. += {"ger_impl_addr": $ger_impl_addr}' /opt/zkevm-contracts/sovereign-rollup-out.json >/opt/zkevm-contracts/sovereign-rollup-out.json.temp && mv /opt/zkevm-contracts/sovereign-rollup-out.json.temp /opt/zkevm-contracts/sovereign-rollup-out.json
jq --arg ger_proxy_addr "$ger_proxy_addr" '. += {"ger_proxy_addr": $ger_proxy_addr}' /opt/zkevm-contracts/sovereign-rollup-out.json >/opt/zkevm-contracts/sovereign-rollup-out.json.temp && mv /opt/zkevm-contracts/sovereign-rollup-out.json.temp /opt/zkevm-contracts/sovereign-rollup-out.json
jq --arg bridge_proxy_addr "$bridge_proxy_addr" '. += {"bridge_proxy_addr": $bridge_proxy_addr}' /opt/zkevm-contracts/sovereign-rollup-out.json >/opt/zkevm-contracts/sovereign-rollup-out.json.temp && mv /opt/zkevm-contracts/sovereign-rollup-out.json.temp /opt/zkevm-contracts/sovereign-rollup-out.json

# Extract values from sovereign-rollup-out.json
sovereignRollupContract=$(jq -r '.sovereignRollupContract' /opt/zkevm-contracts/sovereign-rollup-out.json)
rollupChainID=$(jq -r '.rollupChainID' /opt/zkevm-contracts/sovereign-rollup-out.json)
verifier=$(jq -r '.verifier' /opt/zkevm-contracts/sovereign-rollup-out.json)
forkID=$(jq -r '.forkID' /opt/zkevm-contracts/sovereign-rollup-out.json)
lastLocalExitRoot=$(jq -r '.lastLocalExitRoot' /opt/zkevm-contracts/sovereign-rollup-out.json)
lastBatchSequenced=$(jq -r '.lastBatchSequenced' /opt/zkevm-contracts/sovereign-rollup-out.json)
lastVerifiedBatch=$(jq -r '.lastVerifiedBatch' /opt/zkevm-contracts/sovereign-rollup-out.json)
_legacyLastPendingState=$(jq -r '._legacyLastPendingState' /opt/zkevm-contracts/sovereign-rollup-out.json)
_legacyLastPendingStateConsolidated=$(jq -r '._legacyLastPendingStateConsolidated' /opt/zkevm-contracts/sovereign-rollup-out.json)
lastVerifiedBatchBeforeUpgrade=$(jq -r '.lastVerifiedBatchBeforeUpgrade' /opt/zkevm-contracts/sovereign-rollup-out.json)
rollupTypeID=$(jq -r '.rollupTypeID' /opt/zkevm-contracts/sovereign-rollup-out.json)
rollupVerifierType=$(jq -r '.rollupVerifierType' /opt/zkevm-contracts/sovereign-rollup-out.json)
bridge_impl_addr=$(jq -r '.bridge_impl_addr' /opt/zkevm-contracts/sovereign-rollup-out.json)
ger_impl_addr=$(jq -r '.ger_impl_addr' /opt/zkevm-contracts/sovereign-rollup-out.json)
ger_proxy_addr=$(jq -r '.ger_proxy_addr' /opt/zkevm-contracts/sovereign-rollup-out.json)
bridge_proxy_addr=$(jq -r '.bridge_proxy_addr' /opt/zkevm-contracts/sovereign-rollup-out.json)

# Update existing fields and append new ones to combined.json
jq --arg ger_proxy_addr "$ger_proxy_addr" \
    --arg bridge_proxy_addr "$bridge_proxy_addr" \
    --arg rollupTypeID "$rollupTypeID" \
    --arg verifier "$verifier" \
    --arg sovereignRollupContract "$sovereignRollupContract" \
    --arg rollupChainID "$rollupChainID" \
    --arg forkID "$forkID" \
    --arg lastLocalExitRoot "$lastLocalExitRoot" \
    --arg lastBatchSequenced "$lastBatchSequenced" \
    --arg lastVerifiedBatch "$lastVerifiedBatch" \
    --arg _legacyLastPendingState "$_legacyLastPendingState" \
    --arg _legacyLastPendingStateConsolidated "$_legacyLastPendingStateConsolidated" \
    --arg lastVerifiedBatchBeforeUpgrade "$lastVerifiedBatchBeforeUpgrade" \
    --arg rollupVerifierType "$rollupVerifierType" \
    '.polygonZkEVMGlobalExitRootL2Address = $ger_proxy_addr |
    .polygonZkEVML2BridgeAddress = $bridge_proxy_addr |
    .rollupTypeId = $rollupTypeID |
    .verifierAddress = $verifier |
    .rollupAddress = $sovereignRollupContract |
    .rollupChainID = $rollupChainID |
    .forkID = $forkID |
    .lastLocalExitRoot = $lastLocalExitRoot |
    .lastBatchSequenced = $lastBatchSequenced |
    .lastVerifiedBatch = $lastVerifiedBatch |
    ._legacyLastPendingState = $_legacyLastPendingState |
    ._legacyLastPendingStateConsolidated = $_legacyLastPendingStateConsolidated |
    .lastVerifiedBatchBeforeUpgrade = $lastVerifiedBatchBeforeUpgrade |
    .rollupVerifierType = $rollupVerifierType' \
    "/opt/zkevm/combined{{.deployment_suffix}}.json" >"/opt/zkevm/combined{{.deployment_suffix}}.json.temp" &&
    mv "/opt/zkevm/combined{{.deployment_suffix}}.json.temp" "/opt/zkevm/combined{{.deployment_suffix}}.json"
