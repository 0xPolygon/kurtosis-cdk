#!/bin/bash
# This script is responsible for deploying the contracts for zkEVM/CDK.
set -x

echo_ts() {
    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo "$timestamp $1"
}

wait_for_rpc_to_be_available() {
    rpc_url="$1"
    counter=0
    max_retries=20
    until cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value 0 "{{.zkevm_l2_sequencer_address}}"; do
        ((counter++))
        echo_ts "L1 RPC might not be ready... Retrying ($counter)..."
        if [ $counter -ge $max_retries ]; then
            echo_ts "Exceeded maximum retry attempts. Exiting."
            exit 1
        fi
        sleep 5
    done
}

wait_for_finalized_block() {
    counter=0
    max_retries=100
    until cast block --rpc-url "{{.l1_rpc_url}}" finalized; do
        ((counter++))
        echo_ts "L1 RPC might not be ready... Retrying ($counter)..."
        if [[ $counter -ge $max_retries ]]; then
            echo_ts "Exceeded maximum retry attempts. Exiting."
            exit 1
        fi
        sleep 5
    done
}

fund_account_on_l1() {
    name="$1"
    address="$2"
    echo_ts "Funding $name account"
    cast send \
        --rpc-url "{{.l1_rpc_url}}" \
        --mnemonic "{{.l1_preallocated_mnemonic}}" \
        --value "{{.l1_funding_amount}}" \
        "$address"
}

mint_gas_token_on_l1() {
    address="$1"
    echo_ts "Minting POL to $address"
    cast send \
        --rpc-url "{{.l1_rpc_url}}" \
        --private-key "{{.zkevm_l2_admin_private_key}}" \
        "{{.zkevm_gas_token_address}}" 'mint(address,uint256)' "$address" 10000000000000000000000
}

# We want to avoid running this script twice.
# In the future it might make more sense to exit with an error code.
# We want to run this script again when deploying a second CDK.
# shellcheck disable=SC1054,SC1083
{{if .deploy_agglayer}}
if [[ -e "/opt/zkevm/.init-complete.lock" ]]; then
    2>&1 echo "This script has already been executed"
    exit 1
fi
# If there is already a successful deployment with an Agglayer service 
# then we want to deploy the rollup onchain to attach it.
{{else}}
if [[ -e "/opt/zkevm/.init-complete.lock" ]]; then
fund_account_on_l1 "admin-002" "{{.zkevm_l2_admin_address}}"

echo_ts "Deploying rollup onchain using the L1 rollup manager contract"
rpc_url="{{.l1_rpc_url}}"
rollup_manager_address="{{.rollup_manager_address}}"
zkevm_rollup_manager_deployer="{{.zkevm_rollup_manager_deployer}}"
zkevm_rollup_manager_deployer_private_key="{{.zkevm_rollup_manager_deployer_private_key}}"
zkevm_rollup_type_id="{{.zkevm_rollup_type_id}}"
zkevm_rollup_chain_id="{{.zkevm_rollup_chain_id}}"
zkevm_l2_admin_address="{{.zkevm_l2_admin_address}}"
zkevm_l2_sequencer_address="{{.zkevm_l2_sequencer_address}}"
zkevm_gas_token_address="{{.zkevm_gas_token_address}}"
zkevm_l2_sequencer_url="http://zkevm-node-sequencer{{.deployment_suffix}}:8123"
zkevm_network_name="Kurtosis CDK"
tx_input=$(cast calldata 'createNewRollup(uint32,uint64,address,address,address,string,string)' "$zkevm_rollup_type_id" "$zkevm_rollup_chain_id" "$zkevm_l2_admin_address" "$zkevm_l2_sequencer_address" "$zkevm_gas_token_address"  "$zkevm_l2_sequencer_url" "$zkevm_network_name")
cast send --private-key $zkevm_rollup_manager_deployer_private_key --rpc-url $rpc_url $rollup_manager_address $tx_input --legacy
echo_ts "Onchain rollup has been created"

echo_ts "Retrieve rollup data"
pushd /opt/zkevm-contracts || exit 1
jq '.polygonRollupManagerAddress = "{{.rollup_manager_address}}"' /opt/zkevm-contracts/tools/getRollupData/rollupDataParams.json.example > /opt/zkevm-contracts/tools/getRollupData/tmp && mv  /opt/zkevm-contracts/tools/getRollupData/tmp  /opt/zkevm-contracts/tools/getRollupData/rollupDataParams.json
jq '.rollupID = {{.zkevm_rollup_id}}' /opt/zkevm-contracts/tools/getRollupData/rollupDataParams.json > /opt/zkevm-contracts/tools/getRollupData/tmp && mv  /opt/zkevm-contracts/tools/getRollupData/tmp  /opt/zkevm-contracts/tools/getRollupData/rollupDataParams.json
awk '!/upgradeToULxLyBlockNumber/' /opt/zkevm-contracts/tools/getRollupData/getRollupData.ts > /opt/zkevm-contracts/tools/getRollupData/tmp && mv /opt/zkevm-contracts/tools/getRollupData/tmp /opt/zkevm-contracts/tools/getRollupData/getRollupData.ts
sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' /opt/zkevm-contracts/hardhat.config.ts
npx hardhat run --network localhost /opt/zkevm-contracts/tools/getRollupData/getRollupData.ts
sed -i 's#{{.l1_rpc_url}}#http://127.0.0.1:8545#' /opt/zkevm-contracts/hardhat.config.ts
fi
{{end}}

# Wait for the L1 RPC to be available.
echo_ts "Waiting for the L1 RPC to be available"
wait_for_rpc_to_be_available "{{.l1_rpc_url}}"
echo_ts "L1 RPC is now available"

if [[ -e "/opt/contract-deploy/genesis.json" && -e "/opt/contract-deploy/combined.json" ]]; then
    2>&1 echo "We have a genesis and combined output file from a previous deployment"
    cp /opt/contract-deploy/* /opt/zkevm/
    exit
else
    2>&1 echo "No previous output detected. Starting clean contract deployment"
fi

# Fund accounts on L1.
echo_ts "Funding important accounts on l1"
fund_account_on_l1 "admin" "{{.zkevm_l2_admin_address}}"
fund_account_on_l1 "sequencer" "{{.zkevm_l2_sequencer_address}}"
fund_account_on_l1 "aggregator" "{{.zkevm_l2_aggregator_address}}"
fund_account_on_l1 "agglayer" "{{.zkevm_l2_agglayer_address}}"
fund_account_on_l1 "claimtxmanager" "{{.zkevm_l2_claimtxmanager_address}}"

# Only fund POL for attaching CDK.
# shellcheck disable=SC1054,SC1083
{{if not .deploy_agglayer}}
mint_gas_token_on_l1 "{{.zkevm_l2_admin_address}}"
mint_gas_token_on_l1 "{{.zkevm_l2_sequencer_address}}"
mint_gas_token_on_l1 "{{.zkevm_l2_aggregator_address}}"
mint_gas_token_on_l1 "{{.zkevm_l2_agglayer_address}}"
mint_gas_token_on_l1 "{{.zkevm_l2_claimtxmanager_address}}"
mint_gas_token_on_l1 "{{.zkevm_l2_timelock_address}}"
mint_gas_token_on_l1 "{{.zkevm_l2_loadtest_address}}"
mint_gas_token_on_l1 "{{.zkevm_l2_dac_address}}"
mint_gas_token_on_l1 "{{.zkevm_l2_proofsigner_address}}"
{{end}}

# Configure zkevm contract deploy parameters.
pushd /opt/zkevm-contracts || exit 1
cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts

# Deploy gas token.
# shellcheck disable=SC1054,SC1083
{{if .zkevm_use_gas_token_contract}}
echo_ts "Deploying gas token to L1"
printf "[profile.default]\nsrc = 'contracts'\nout = 'out'\nlibs = ['node_modules']\n" > foundry.toml
forge create \
    --json \
    --rpc-url "{{.l1_rpc_url}}" \
    --mnemonic "{{.l1_preallocated_mnemonic}}" \
    contracts/mocks/ERC20PermitMock.sol:ERC20PermitMock \
    --constructor-args  "CDK Gas Token" "CDK" "{{.zkevm_l2_admin_address}}" "1000000000000000000000000" > gasToken-erc20.json

# In this case, we'll configure the create rollup parameters to have a gas token
jq --slurpfile c gasToken-erc20.json '.gasTokenAddress = $c[0].deployedTo' /opt/contract-deploy/create_rollup_parameters.json > /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
# shellcheck disable=SC1056,SC1072,SC1073,SC1009
{{end}}

# Deploy the DAC contracts if deploying an attaching CDK.
# Then transfer ownership, and activate the DAC.
# shellcheck disable=SC1054,SC1083
{{if not .deploy_agglayer}}
pushd /opt/zkevm-contracts || exit 1
echo_ts "Deploying DAC for attaching CDK"
jq '.admin = "{{.zkevm_l2_admin_address}}"' /opt/zkevm-contracts/tools/deployPolygonDataCommittee/deploy_dataCommittee_parameters.example > /opt/zkevm-contracts/tools/deployPolygonDataCommittee/tmp && mv /opt/zkevm-contracts/tools/deployPolygonDataCommittee/tmp /opt/zkevm-contracts/tools/deployPolygonDataCommittee/deploy_dataCommittee_parameters.json
jq '.deployerPvtKey = "{{.zkevm_rollup_manager_deployer_private_key}}"' /opt/zkevm-contracts/tools/deployPolygonDataCommittee/deploy_dataCommittee_parameters.json > /opt/zkevm-contracts/tools/deployPolygonDataCommittee/tmp && mv /opt/zkevm-contracts/tools/deployPolygonDataCommittee/tmp /opt/zkevm-contracts/tools/deployPolygonDataCommittee/deploy_dataCommittee_parameters.json
npx hardhat run /opt/zkevm-contracts/tools/deployPolygonDataCommittee/deployPolygonDataCommittee.ts --network localhost > /opt/zkevm-contracts/tools/deployPolygonDataCommittee/output.json

# Transfer ownership of the deployed DAC.
echo_ts "Transferring ownership of the DAC"
dac_address=$(grep "PolygonDataCommittee deployed to:" /opt/zkevm-contracts/tools/deployPolygonDataCommittee/output.json | awk '{print $NF}')
cast call --rpc-url "{{.l1_rpc_url}}" $dac_address 'owner()(address)'
cast send --private-key "{{.zkevm_rollup_manager_deployer_private_key}}" --rpc-url "{{.l1_rpc_url}}" $dac_address 'transferOwnership(address)' "{{.zkevm_l2_admin_address}}"
{{end}}

# Deploy contracts.
echo_ts "Deploying zkevm contracts to L1"

echo_ts "Step 1: Preparing tesnet"
npx hardhat run deployment/testnet/prepareTestnet.ts --network localhost | tee 01_prepare_testnet.out

echo_ts "Step 2: Creating genesis"
MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts | tee 02_create_genesis.out

echo_ts "Step 3: Deploying PolygonZKEVMDeployer"
npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost | tee 03_zkevm_deployer.out

echo_ts "Step 4: Deploying contracts"
npx hardhat run deployment/v2/3_deployContracts.ts --network localhost | tee 04_deploy_contracts.out

echo_ts "Step 5: Creating rollup"
npx hardhat run deployment/v2/4_createRollup.ts --network localhost | tee 05_create_rollup.out

# Combine contract deploy files.
# At this point, all of the contracts /should/ have been deployed.
# Now we can combine all of the files and put them into the general zkevm folder.
echo_ts "Combining contract deploy files"
mkdir -p /opt/zkevm
cp /opt/zkevm-contracts/deployment/v2/deploy_*.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/create_rollup_output.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json /opt/zkevm/
popd

# Combine contract deploy data.
pushd /opt/zkevm/ || exit 1
echo_ts "Creating combined.json"
cp genesis.json genesis.original.json
jq --slurpfile rollup create_rollup_output.json '. + $rollup[0]' deploy_output.json > combined.json
# Extract L2 Bridge contract address.
polygonZkEVML2BridgeAddress=$(grep "PolygonZkEVMBridge deployed to:" /opt/zkevm-contracts/04_deploy_contracts.out | awk '{print $NF}')
jq --arg polygonZkEVML2BridgeAddress "$polygonZkEVML2BridgeAddress" '.polygonZkEVML2BridgeAddress = $polygonZkEVML2BridgeAddress' combined.json > c.json; mv c.json combined.json

# Add the L2 GER Proxy address in combined.json (for panoptichain).
zkevm_global_exit_root_l2_address=$(jq -r '.genesis[] | select(.contractName == "PolygonZkEVMGlobalExitRootL2 proxy") | .address' /opt/zkevm/genesis.json)
jq --arg a "$zkevm_global_exit_root_l2_address" '.polygonZkEVMGlobalExitRootL2Address = $a' combined.json > c.json; mv c.json combined.json

# There are a bunch of fields that need to be renamed in order for the
# older fork7 code to be compatible with some of the fork8
# automations. This schema matching can be dropped once this is
# versioned up to 8
fork_id="{{.zkevm_rollup_fork_id}}"
if [[ fork_id -lt 8 ]]; then
    jq '.polygonRollupManagerAddress = .polygonRollupManager' combined.json > c.json; mv c.json combined.json
    jq '.deploymentRollupManagerBlockNumber = .deploymentBlockNumber' combined.json > c.json; mv c.json combined.json
    jq '.upgradeToULxLyBlockNumber = .deploymentBlockNumber' combined.json > c.json; mv c.json combined.json
    jq '.polygonDataCommitteeAddress = .polygonDataCommittee' combined.json > c.json; mv c.json combined.json
    jq '.createRollupBlockNumber = .createRollupBlock' combined.json > c.json; mv c.json combined.json
fi

# NOTE there is a disconnect in the necessary configurations here between the validium node and the zkevm node
# shellcheck disable=SC1054,SC1083
{{if .deploy_agglayer}}
jq --slurpfile c combined.json '.rollupCreationBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.rollupManagerCreationBlockNumber = $c[0].upgradeToULxLyBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.genesisBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config = {chainId:{{.l1_chain_id}}}' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonZkEVMGlobalExitRootAddress = $c[0].polygonZkEVMGlobalExitRootAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonRollupManagerAddress = $c[0].polygonRollupManagerAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polTokenAddress = $c[0].polTokenAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonZkEVMAddress = $c[0].rollupAddress' genesis.json > g.json; mv g.json genesis.json

jq --slurpfile c combined.json '.bridgeGenBlockNumber = $c[0].createRollupBlockNumber' combined.json > c.json; mv c.json combined.json

{{else}}
rollupCreationBlockNumber=$(jq -r '.createRollupBlockNumber' /opt/zkevm-contracts/tools/getRollupData/create_rollup_output.json)
rollupManagerCreationBlockNumber=$(jq -r '.deploymentRollupManagerBlockNumber' /opt/zkevm-contracts/tools/getRollupData/deploy_output.json)
genesisBlockNumber=$(jq -r '.createRollupBlockNumber' /opt/zkevm-contracts/tools/getRollupData/create_rollup_output.json)
polygonZkEVMGlobalExitRootAddress=$(jq -r '.polygonZkEVMGlobalExitRootAddress' /opt/zkevm-contracts/tools/getRollupData/deploy_output.json)
polygonRollupManagerAddress=$(jq -r '.polygonRollupManagerAddress' /opt/zkevm-contracts/tools/getRollupData/deploy_output.json)
polTokenAddress=$(jq -r '.polTokenAddress' /opt/zkevm-contracts/tools/getRollupData/deploy_output.json)
polygonZkEVMAddress=$(jq -r '.rollupAddress' /opt/zkevm-contracts/tools/getRollupData/create_rollup_output.json)
polygonZkEVMBridgeAddress=$(cast call --rpc-url "{{.l1_rpc_url}}" "$polygonRollupManagerAddress" "bridgeAddress()(address)")

jq --argjson rollupCreationBlockNumber "$rollupCreationBlockNumber" '.rollupCreationBlockNumber = $rollupCreationBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --argjson rollupManagerCreationBlockNumber "$rollupManagerCreationBlockNumber" '.rollupManagerCreationBlockNumber = $rollupManagerCreationBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --argjson genesisBlockNumber "$genesisBlockNumber" '.genesisBlockNumber = $genesisBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq '.L1Config = {chainId:{{.l1_chain_id}}}' genesis.json > g.json; mv g.json genesis.json
jq --arg polygonZkEVMGlobalExitRootAddress "$polygonZkEVMGlobalExitRootAddress" '.L1Config.polygonZkEVMGlobalExitRootAddress = $polygonZkEVMGlobalExitRootAddress' genesis.json > g.json; mv g.json genesis.json
jq --arg polygonRollupManagerAddress "$polygonRollupManagerAddress" '.L1Config.polygonRollupManagerAddress = $polygonRollupManagerAddress' genesis.json > g.json; mv g.json genesis.json
jq --arg polTokenAddress "$polTokenAddress" '.L1Config.polTokenAddress = $polTokenAddress' genesis.json > g.json; mv g.json genesis.json
jq --arg polygonZkEVMAddress "$polygonZkEVMAddress" '.L1Config.polygonZkEVMAddress = $polygonZkEVMAddress' genesis.json > g.json; mv g.json genesis.json

# Extract newly deployed DAC address and genesisBlockNumber
polygonDataCommitteeAddress=$(grep "PolygonDataCommittee deployed to:" /opt/zkevm-contracts/tools/deployPolygonDataCommittee/output.json | awk '{print $NF}')
jq --arg polygonDataCommitteeAddress "$polygonDataCommitteeAddress" '.polygonDataCommitteeAddress = $polygonDataCommitteeAddress' combined.json > c.json; mv c.json combined.json
jq --arg polygonZkEVMAddress "$polygonZkEVMAddress" '.rollupAddress = $polygonZkEVMAddress' combined.json > c.json; mv c.json combined.json
jq --arg genesisBlockNumber "$genesisBlockNumber" '.bridgeGenBlockNumber = $genesisBlockNumber' combined.json > c.json; mv c.json combined.json
{{end}}

# Create cdk-erigon node configs
jq_script='
.genesis | map({
  (.address): {
    contractName: (if .contractName == "" then null else .contractName end),
    balance: (if .balance == "" then null else .balance end),
    nonce: (if .nonce == "" then null else .nonce end),
    code: (if .bytecode == "" then null else .bytecode end),
    storage: (if .storage == null or .storage == {} then null else (.storage | to_entries | sort_by(.key) | from_entries) end)
  }
}) | add'

# Use jq to transform the input JSON into the desired format
output_json=$(jq "$jq_script" /opt/zkevm/genesis.json)

# Handle jq errors
if [[ $? -ne 0 ]]; then
    echo "Error processing JSON with jq"
    exit 1
fi

# Write the output JSON to a file
echo "$output_json" | jq . > dynamic-kurtosis-allocs.json
if [[ $? -ne 0 ]]; then
    echo "Error writing to file dynamic-kurtosis-allocs.json"
    exit 1
fi

echo "Transformation complete. Output written to dynamic-kurtosis-allocs.json"

jq '{"root": .root, "timestamp": 0, "gasLimit": 0, "difficulty": 0}' /opt/zkevm/genesis.json > dynamic-kurtosis-conf.json

batch_timestamp=$(jq '.firstBatchData.timestamp' combined.json)

jq --arg bt "$batch_timestamp" '.timestamp |= ($bt | tonumber)' dynamic-kurtosis-conf.json > tmp_output.json

mv tmp_output.json dynamic-kurtosis-conf.json

cat dynamic-kurtosis-conf.json

# Configure contracts.

# The sequencer needs to pay POL when it sequences batches.
# This gets refunded when the batches are proved.
# In order for this to work t,he rollup address must be approved to transfer the sequencers' POL tokens.
echo_ts "Approving the rollup address to transfer POL tokens on behalf of the sequencer"
cast send \
    --private-key "{{.zkevm_l2_sequencer_private_key}}" \
    --legacy \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polTokenAddress' combined.json)" \
    'approve(address,uint256)(bool)' \
    "$(jq -r '.rollupAddress' combined.json)" 1000000000000000000000000000

{{if and .is_cdk_validium .deploy_agglayer}}
# The DAC needs to be configured with a required number of signatures.
# Right now the number of DAC nodes is not configurable.
# If we add more nodes, we'll need to make sure the urls and keys are sorted.
echo_ts "Setting the data availability committee"
cast send \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polygonDataCommitteeAddress' combined.json)" \
    'function setupCommittee(uint256 _requiredAmountOfSignatures, string[] urls, bytes addrsBytes) returns()' \
    1 ["http://zkevm-dac{{.deployment_suffix}}:{{.zkevm_dac_port}}"] "{{.zkevm_l2_dac_address}}"

# The DAC needs to be enabled with a call to set the DA protocol.
echo_ts "Setting the data availability protocol"
cast send \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.rollupAddress' combined.json)" \
    'setDataAvailabilityProtocol(address)' \
    "$(jq -r '.polygonDataCommitteeAddress' combined.json)"
{{else}}
echo_ts "Setting the data availability committee"
dac_address=$(grep "PolygonDataCommittee deployed to:" /opt/zkevm-contracts/tools/deployPolygonDataCommittee/output.json | awk '{print $NF}')
cast send \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    $dac_address \
    'function setupCommittee(uint256 _requiredAmountOfSignatures, string[] urls, bytes addrsBytes) returns()' \
    1 ["http://zkevm-dac{{.deployment_suffix}}:{{.zkevm_dac_port}}"] "{{.zkevm_l2_dac_address}}"

echo_ts "Activate the DAC"
rollup_address=$(jq -r '.rollupAddress' /opt/zkevm-contracts/tools/getRollupData/create_rollup_output.json)
dac_address=$(grep "PolygonDataCommittee deployed to:" /opt/zkevm-contracts/tools/deployPolygonDataCommittee/output.json | awk '{print $NF}')
cast call --rpc-url "{{.l1_rpc_url}}" $rollup_address 'dataAvailabilityProtocol()'
cast send --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}" $rollup_address 'setDataAvailabilityProtocol(address)' $dac_address
{{end}}

{{if .deploy_agglayer}}
# Grant the aggregator role to the agglayer so that it can also verify batches.
# cast keccak "TRUSTED_AGGREGATOR_ROLE"
echo_ts "Granting the aggregator role to the agglayer so that it can also verify batches"
cast send \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polygonRollupManagerAddress' combined.json)" \
    'grantRole(bytes32,address)' \
    "0x084e94f375e9d647f87f5b2ceffba1e062c70f6009fdbcf80291e803b5c9edd4" "{{.zkevm_l2_agglayer_address}}"
{{else}}
echo_ts "Granting the aggregator role to the agglayer so that it can also verify batches"
polygonRollupManagerAddress=$(jq -r '.polygonRollupManagerAddress' /opt/zkevm-contracts/tools/getRollupData/deploy_output.json)
cast send \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    $polygonRollupManagerAddress \
    'grantRole(bytes32,address)' \
    "0x084e94f375e9d647f87f5b2ceffba1e062c70f6009fdbcf80291e803b5c9edd4" "{{.zkevm_l2_agglayer_address}}"
{{end}}


# If we've configured the l1 network with the minimal preset, we
# should probably wait for the first finalized block. This isn't
# strictly specific to minimal preset, but if we don't have "minimal"
# configured, it's going to take like 25 minutes for the first
# finalized block
l1_preset="{{.l1_preset}}"
if [[ $l1_preset == "minimal" ]]; then
    wait_for_finalized_block;
fi

# The contract setup is done!
touch .init-complete.lock
