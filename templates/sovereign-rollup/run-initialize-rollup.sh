#!/usr/bin/env bash
set -e
# Initialize rollup
pushd /opt/zkevm-contracts || exit 1

ts=$(date +%s)
# The startingBlockNumber and sp1_starting_timestamp values in create_new_rollup.json file needs to be populated with the below commands.
deployOPSuccinct="{{ .deploy_op_succinct }}"
if [[ $deployOPSuccinct == true ]]; then
echo "Configuring OP Succinct setup..."
jq --slurpfile l2 /opt/contract-deploy/opsuccinctl2ooconfig.json '
.deployerPvtKey = .aggchainManagerPvtKey |
.aggchainParams.initParams.l2BlockTime = $l2[0].l2BlockTime |
.aggchainParams.initParams.rollupConfigHash = $l2[0].rollupConfigHash |
.aggchainParams.initParams.startingOutputRoot = $l2[0].startingOutputRoot |
.aggchainParams.initParams.startingTimestamp = $l2[0].startingTimestamp |
.aggchainParams.initParams.startingBlockNumber = $l2[0].startingBlockNumber |
.aggchainParams.initParams.submissionInterval = $l2[0].submissionInterval |
.aggchainParams.initParams.aggregationVkey = $l2[0].aggregationVkey |
.aggchainParams.initParams.rangeVkeyCommitment = $l2[0].rangeVkeyCommitment
' /opt/contract-deploy/create_new_rollup.json > /opt/contract-deploy/initialize_rollup.json

jq --slurpfile l2 /opt/contract-deploy/opsuccinctl2ooconfig.json \ '.verifierAddress = $l2[0].verifier' /opt/contract-deploy/initialize_rollup.json > "/opt/contract-deploy/initialize_rollup${ts}".json
cp "/opt/contract-deploy/initialize_rollup${ts}.json" /opt/contract-deploy/initialize_rollup.json

# Extract the rollup manager address from the JSON file. .zkevm_rollup_manager_address is not available at the time of importing this script.
# So a manual extraction of polygonRollupManagerAddress is done here.
# Even with multiple op stack deployments, the rollup manager address can be retrieved from combined{{.deployment_suffix}}.json because it must be constant.
rollup_manager_addr=$(jq -r '.rollupManagerAddress' /opt/zkevm/create_rollup_output.json)
rollup_id=$(jq -r '.rollupID' /opt/zkevm/create_rollup_output.json)

# It looks like setting up of the rollupid isn't necessary because the rollupid is determined based on the chainid
jq --arg rum "$rollup_manager_addr" --arg rid "$rollup_id" --arg chainid "{{.zkevm_rollup_chain_id}}" '.rollupManagerAddress = $rum | .rollupID = $rid | .chainID = ($chainid | tonumber)' /opt/contract-deploy/initialize_rollup.json > /opt/contract-deploy/initialize_rollup.json.tmp
mv /opt/contract-deploy/initialize_rollup.json.tmp /opt/contract-deploy/initialize_rollup.json

cp /opt/contract-deploy/initialize_rollup.json /opt/zkevm-contracts/tools/initializeRollup/initialize_rollup.json

npx hardhat run tools/initializeRollup/initializeRollup.ts --network localhost 2>&1 | tee 08_init_rollup.out
fi

# Save Rollup Information to a file.
rollup_manager_addr=$(jq -r '.polygonRollupManagerAddress' /opt/zkevm/combined.json)
cast call --json --rpc-url "{{.l1_rpc_url}}" "$rollup_manager_addr" 'rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' "{{.zkevm_rollup_id}}" | jq '{"sovereignRollupContract": .[0], "rollupChainID": .[1], "verifier": .[2], "forkID": .[3], "lastLocalExitRoot": .[4], "lastBatchSequenced": .[5], "lastVerifiedBatch": .[6], "_legacyLastPendingState": .[7], "_legacyLastPendingStateConsolidated": .[8], "lastVerifiedBatchBeforeUpgrade": .[9], "rollupTypeID": .[10], "rollupVerifierType": .[11]}' > /opt/zkevm-contracts/sovereign-rollup-out.json

# These are some accounts that we want to fund for operations for running claims.
bridge_admin_addr="{{.zkevm_l2_sovereignadmin_address}}"
# bridge_admin_private_key="{{.zkevm_l2_sovereignadmin_private_key}}"
aggoracle_addr="{{.zkevm_l2_aggoracle_address}}"
# aggoracle_private_key="{{.zkevm_l2_aggoracle_private_key}}"
claimtxmanager_addr="{{.zkevm_l2_claimtxmanager_address}}"
# claimtx_private_key="{{.zkevm_l2_claimtxmanager_private_key}}"
claimsponsor_addr="{{.zkevm_l2_claimsponsor_address}}"
# claimsponsor_private_key="{{.zkevm_l2_claimsponsor_private_key}}"

rpc_url="{{.op_el_rpc_url}}"
# This is the default prefunded account for the OP Network
private_key=$(cast wallet private-key --mnemonic 'test test test test test test test test test test test junk')

cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $bridge_admin_addr
cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $aggoracle_addr
cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $claimtxmanager_addr
cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $claimsponsor_addr

# Contract Deployment Step
# cd /opt/zkevm-contracts || exit

# echo "[profile.default]
# src = 'contracts'
# out = 'out'
# libs = ['node_modules']" >foundry.toml

# echo "Building contracts with forge build"
# forge build contracts/v2/sovereignChains/BridgeL2SovereignChain.sol contracts/v2/sovereignChains/GlobalExitRootManagerL2SovereignChain.sol
# bridge_impl_nonce=$(cast nonce --rpc-url $rpc_url $bridge_admin_addr)
# bridge_impl_addr=$(cast compute-address --nonce "$bridge_impl_nonce" $bridge_admin_addr | sed 's/.*: //')
# ger_impl_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 1)) $bridge_admin_addr | sed 's/.*: //')
# ger_proxy_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 2)) $bridge_admin_addr | sed 's/.*: //')
# bridge_proxy_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 3)) $bridge_admin_addr | sed 's/.*: //')

# It seems like the structure of the genesis output must have changed. This structure doesn't look like it makes sense anymore
# bridge_impl_addr=$(jq -r '.genesis[] | select(.contractName == "BridgeL2SovereignChain implementation") | .address' /opt/zkevm/sovereign-predeployed-genesis.json)
# bridge_proxy_addr=$(jq -r '.genesis[] | select(.contractName == "BridgeL2SovereignChain proxy") | .address' /opt/zkevm/sovereign-predeployed-genesis.json)
# ger_impl_addr=$(jq -r '.genesis[] | select(.contractName == "GlobalExitRootManagerL2SovereignChain implementation") | .address' /opt/zkevm/sovereign-predeployed-genesis.json)
# ger_proxy_addr=$(jq -r '.genesis[] | select(.contractName == "GlobalExitRootManagerL2SovereignChain proxy") | .address' /opt/zkevm/sovereign-predeployed-genesis.json)

bridge_impl_addr=$(jq -r '.genesisSCNames["BridgeL2SovereignChain implementation"]' /opt/zkevm/create-sovereign-genesis-output.json)
bridge_proxy_addr=$(jq -r '.genesisSCNames["BridgeL2SovereignChain proxy"]' /opt/zkevm/create-sovereign-genesis-output.json)
ger_impl_addr=$(jq -r '.genesisSCNames["GlobalExitRootManagerL2SovereignChain implementation"]' /opt/zkevm/create-sovereign-genesis-output.json)
ger_proxy_addr=$(jq -r '.genesisSCNames["GlobalExitRootManagerL2SovereignChain proxy"]' /opt/zkevm/create-sovereign-genesis-output.json)

# This is one way to prefund the bridge. It can also be done with a deposit to some unclaimable network. This step is important and needs to be discussed
# cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" "$bridge_proxy_addr"
# forge create --legacy --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key BridgeL2SovereignChain
# forge create --legacy --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key GlobalExitRootManagerL2SovereignChain --constructor-args "$bridge_proxy_addr"
# calldata=$(cast calldata 'initialize(address _globalExitRootUpdater, address _globalExitRootRemover)' $aggoracle_addr $aggoracle_addr)
# forge create --legacy --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key TransparentUpgradeableProxy --constructor-args "$ger_impl_addr" $bridge_admin_addr "$calldata"

# initNetworkID="{{.zkevm_rollup_id}}"
# initGasTokenAddress=$(cast az)
# initGasTokenNetwork=0
# initGlobalExitRootManager=$ger_proxy_addr
# initPolygonRollupManager=$(cast az)
# initGasTokenMetadata=0x
# initBridgeManager=$bridge_admin_addr
# initSovereignWETHAddress=$(cast az)
# initSovereignWETHAddressIsNotMintable=false

# calldata=$(cast calldata 'function initialize(uint32 _networkID, address _gasTokenAddress, uint32 _gasTokenNetwork, address _globalExitRootManager, address _polygonRollupManager, bytes _gasTokenMetadata, address _bridgeManager, address _sovereignWETHAddress, bool _sovereignWETHAddressIsNotMintable)' $initNetworkID "$initGasTokenAddress" $initGasTokenNetwork "$initGlobalExitRootManager" "$initPolygonRollupManager" $initGasTokenMetadata $initBridgeManager "$initSovereignWETHAddress" $initSovereignWETHAddressIsNotMintable)
# forge create --legacy --broadcast --rpc-url $rpc_url --private-key $bridge_admin_private_key TransparentUpgradeableProxy --constructor-args "$bridge_impl_addr" $bridge_admin_addr "$calldata"

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
# bridge_impl_addr=$(jq -r '.bridge_impl_addr' /opt/zkevm-contracts/sovereign-rollup-out.json)
# ger_impl_addr=$(jq -r '.ger_impl_addr' /opt/zkevm-contracts/sovereign-rollup-out.json)
# ger_proxy_addr=$(jq -r '.ger_proxy_addr' /opt/zkevm-contracts/sovereign-rollup-out.json)
# bridge_proxy_addr=$(jq -r '.bridge_proxy_addr' /opt/zkevm-contracts/sovereign-rollup-out.json)

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
    "/opt/zkevm/combined.json" > "/opt/zkevm/combined.json.temp"

mv "/opt/zkevm/combined.json.temp" "/opt/zkevm/combined.json"

# Copy the updated combined.json to a new file with the deployment suffix
cp "/opt/zkevm/combined.json" "/opt/zkevm/combined{{.deployment_suffix}}.json"

# Contract addresses to extract from combined.json and check for bytecode
# shellcheck disable=SC2034
l1_contract_names=(
    "polygonRollupManagerAddress"
    "polygonZkEVMBridgeAddress"
    "polygonZkEVMGlobalExitRootAddress"
    "aggLayerGatewayAddress"
    "pessimisticVKeyRouteALGateway.verifier"
    "polTokenAddress"
    "zkEVMDeployerContract"
    "timelockContractAddress"
    "rollupAddress"
)

# shellcheck disable=SC2034
l2_contract_names=(
    "polygonZkEVML2BridgeAddress"
    "polygonZkEVMGlobalExitRootL2Address"
)

# JSON file to extract addresses from
json_file="/opt/zkevm/combined.json"

# Function to build jq filter and extract addresses
extract_addresses() {
    local -n keys_array=$1  # Reference to the input array
    local json_file=$2      # JSON file path
    local jq_filter=""

    # Build the jq filter
    for key in "${keys_array[@]}"; do
        if [ -z "$jq_filter" ]; then
            jq_filter=".${key}"
        else
            jq_filter="$jq_filter, .${key}"
        fi
    done

    # Extract addresses using jq and return them
    jq -r "[$jq_filter][] | select(. != null)" "$json_file"
}

# Extract addresses
# shellcheck disable=SC2128
l1_contract_addresses=$(extract_addresses l1_contract_names "$json_file")
# shellcheck disable=SC2128
l2_contract_addresses=$(extract_addresses l2_contract_names "$json_file")

check_deployed_contracts() {
    # shellcheck disable=SC2178
    local addresses=$1         # String of space-separated addresses
    local rpc_url=$2           # RPC URL for cast command

    # shellcheck disable=SC2128
    if [[ -z "$addresses" ]]; then
        echo "ERROR: No addresses provided to check"
        exit 1
    fi

    for addr in $addresses; do
        # Get bytecode using cast code with specified RPC URL
        if ! bytecode=$(cast code "$addr" --rpc-url "$rpc_url" 2>/dev/null); then
            echo "Address: $addr - Error checking address (RPC: $rpc_url)"
            continue
        fi

        if [[ $addr == "0x0000000000000000000000000000000000000000" ]]; then
            echo "Warning - The zero address was provide as one of the contracts"
            continue
        fi

        # Check if bytecode is non-zero
        if [[ "$bytecode" == "0x" || -z "$bytecode" ]]; then
            echo "Address: $addr - MISSING BYTECODE AT CONTRACT ADDRESS"
            exit 1
        else
            # Get bytecode length removing 0x prefix and counting hex chars
            byte_length=$(echo "$bytecode" | sed 's/^0x//' | wc -c)
            byte_length=$((byte_length / 2))  # Convert hex chars to bytes
            echo "Address: $addr - DEPLOYED (bytecode length: $byte_length bytes)"
        fi
    done
}

# Check deployed contracts
check_deployed_contracts "$l1_contract_addresses" "{{.l1_rpc_url}}"
check_deployed_contracts "$l2_contract_addresses" "{{.op_el_rpc_url}}"

# Only set the aggchainVkey for the first rollup. Adding multiple aggchainVkeys of the same value will revert with "0x22a1bdc4" or "AggchainVKeyAlreadyExists()".
rollupID=$(cast call "$rollup_manager_addr" "chainIDToRollupID(uint64)(uint32)" "{{.zkevm_rollup_chain_id}}" --rpc-url "{{.l1_rpc_url}}")
# shellcheck disable=SC2050
if [[ $rollupID == "1" ]] && [[ "{{ .consensus_contract_type }}" != "ecdsa_multisig" ]]; then
    # FIXME - Temporary work around to make sure the default aggkey is configured
    cast send --rpc-url "{{.l1_rpc_url}}" --private-key "{{.zkevm_l2_admin_private_key}}" "$(jq -r '.aggLayerGatewayAddress' /opt/zkevm/combined.json)" "addDefaultAggchainVKey(bytes4,bytes32)" "{{.aggchain_vkey_selector}}" "{{.aggchain_vkey_hash}}" 
    true
fi