#!/bin/bash
# shellcheck disable=SC2034,SC2086

# Create New Rollup Step
cd /opt/zkevm-contracts || exit

# This will require genesis.json and create_new_rollup.json to be correctly filled. We are using a pre-defined template for these.
# The script and example files exist under https://github.com/0xPolygonHermez/zkevm-contracts/tree/v9.0.0-rc.5-pp/tools/createNewRollup
# The templates being used here - create_new_rollup.json and genesis.json were directly referenced from the above source.
cp /opt/contract-deploy/create_new_rollup.json /opt/zkevm-contracts/tools/createNewRollup/create_new_rollup.json
cp /opt/contract-deploy/sovereign-genesis.json /opt/zkevm-contracts/tools/createNewRollup/genesis.json

npx hardhat run ./tools/createNewRollup/createNewRollup.ts --network localhost
rollup_manager_addr="0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2"
cast call --json --rpc-url  http://el-1-geth-lighthouse:8545 $rollup_manager_addr 'rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' 2 | jq '{"sovereignRollupContract": .[0], "sovereignChainID": .[1], "verifier": .[2], "forkID": .[3], "lastLocalExitRoot": .[4], "lastBatchSequenced": .[5], "lastVerifiedBatch": .[6], "_legacyLastPendingState": .[7], "_legacyLastPendingStateConsolidated": .[8], "lastVerifiedBatchBeforeUpgrade": .[9], "rollupTypeID": .[10], "rollupVerifierType": .[11]}' > /opt/zkevm-contracts/sovereign-rollup-out.json

# These are some accounts that we want to fund for operations for running claims.
bridge_admin_addr=0x72aA7C55e1c7BF4017F22a3bc19722de11911A81
bridge_admin_private_key=0x5f3556010771f2cc34eb2669401ee1109bc05aed993024ed10ff04ba7309e28b
aggoracle_addr=0x2Ac2c49Ee3Ac5f663115C86F405Ea855B365D5Ec
aggoracle_private_key=0xd65de4634c214d45673528bf55be28fe43b0664c99cc99089ef75a922b3a22fd
claimtx_addr=0x3754Aa77EE1E8AfB200Ce36a8c943ed8F5AaB7BC
claimtx_private_key=0xfa333c42db7bc56277bf67c93ba19e4f414d802ef9886b8b5dc7c450655ae77f

rpc_url=http://op-el-1-op-geth-op-node-op-kurtosis:8545
# This is the default prefunded account for the OP Network
private_key=$(cast wallet private-key --mnemonic 'test test test test test test test test test test test junk')

cast send --value 10ether  --rpc-url $rpc_url --private-key $private_key $bridge_admin_addr
cast send --value 10ether  --rpc-url $rpc_url --private-key $private_key $aggoracle_addr
cast send --value 100ether --rpc-url $rpc_url --private-key $private_key $claimtx_addr

# Contract Deployment Step
cd /opt/zkevm-contracts || exit

echo "[profile.default]
src = 'contracts'
out = 'out'
libs = ['node_modules']" > foundry.toml

echo "Building contracts with forge build"
forge build contracts/v2/sovereignChains/BridgeL2SovereignChain.sol contracts/v2/sovereignChains/GlobalExitRootManagerL2SovereignChain.sol
bridge_impl_nonce=$(cast nonce --rpc-url $rpc_url $bridge_admin_addr)
bridge_impl_addr=$(cast compute-address --nonce $bridge_impl_nonce $bridge_admin_addr | sed 's/.*: //')
ger_impl_addr=$(cast compute-address --nonce $((bridge_impl_nonce+1)) $bridge_admin_addr | sed 's/.*: //')
ger_proxy_addr=$(cast compute-address --nonce $((bridge_impl_nonce+2)) $bridge_admin_addr | sed 's/.*: //')
bridge_proxy_addr=$(cast compute-address --nonce $((bridge_impl_nonce+3)) $bridge_admin_addr | sed 's/.*: //')

# This is one way to prefund the bridge. It can also be done with a deposit to some unclaimable network. This step is important and needs to be discussed
cast send --value 1000ether --rpc-url $rpc_url --private-key $private_key $bridge_proxy_addr
forge create --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key BridgeL2SovereignChain
forge create --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key GlobalExitRootManagerL2SovereignChain --constructor-args $bridge_proxy_addr
calldata=$(cast calldata 'initialize(address _globalExitRootUpdater, address _globalExitRootRemover)' $aggoracle_addr $aggoracle_addr)
forge create --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key TransparentUpgradeableProxy --constructor-args $ger_impl_addr $bridge_admin_addr $calldata

initNetworkID=2
initGasTokenAddress=$(cast az)
initGasTokenNetwork=0
initGlobalExitRootManager=$ger_proxy_addr
initPolygonRollupManager=$(cast az)
initGasTokenMetadata=0x
initBridgeManager=$bridge_admin_addr
initSovereignWETHAddress=$(cast az)
initSovereignWETHAddressIsNotMintable=false

calldata=$(cast calldata 'function initialize(uint32 _networkID, address _gasTokenAddress, uint32 _gasTokenNetwork, address _globalExitRootManager, address _polygonRollupManager, bytes _gasTokenMetadata, address _bridgeManager, address _sovereignWETHAddress, bool _sovereignWETHAddressIsNotMintable)' $initNetworkID $initGasTokenAddress $initGasTokenNetwork $initGlobalExitRootManager $initPolygonRollupManager $initGasTokenMetadata $initBridgeManager $initSovereignWETHAddress $initSovereignWETHAddressIsNotMintable)
forge create --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key TransparentUpgradeableProxy --constructor-args $bridge_impl_addr $bridge_admin_addr $calldata

jq --arg bridge_impl_addr "$bridge_impl_addr" '. += {"bridge_impl_addr": $bridge_impl_addr}' /opt/zkevm-contracts/sovereign-rollup-out.json > /opt/zkevm-contracts/sovereign-rollup-out.json.temp && mv /opt/zkevm-contracts/sovereign-rollup-out.json.temp /opt/zkevm-contracts/sovereign-rollup-out.json
jq --arg ger_impl_addr "$ger_impl_addr" '. += {"ger_impl_addr": $ger_impl_addr}' /opt/zkevm-contracts/sovereign-rollup-out.json > /opt/zkevm-contracts/sovereign-rollup-out.json.temp && mv /opt/zkevm-contracts/sovereign-rollup-out.json.temp /opt/zkevm-contracts/sovereign-rollup-out.json
jq --arg ger_proxy_addr "$ger_proxy_addr" '. += {"ger_proxy_addr": $ger_proxy_addr}' /opt/zkevm-contracts/sovereign-rollup-out.json > /opt/zkevm-contracts/sovereign-rollup-out.json.temp && mv /opt/zkevm-contracts/sovereign-rollup-out.json.temp /opt/zkevm-contracts/sovereign-rollup-out.json
jq --arg bridge_proxy_addr "$bridge_proxy_addr" '. += {"bridge_proxy_addr": $bridge_proxy_addr}' /opt/zkevm-contracts/sovereign-rollup-out.json > /opt/zkevm-contracts/sovereign-rollup-out.json.temp && mv /opt/zkevm-contracts/sovereign-rollup-out.json.temp /opt/zkevm-contracts/sovereign-rollup-out.json