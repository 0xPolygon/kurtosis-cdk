#!/bin/bash
# This script is responsible for deploying the contracts for zkEVM/CDK.

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

# We want to avoid running this script twice.
# In the future it might make more sense to exit with an error code.
if [[ -e "/opt/zkevm/.init-complete.lock" ]]; then
    echo "This script has already been executed"
    exit
fi

# Wait for the L1 RPC to be available.
echo_ts "Waiting for the L1 RPC to be available"
wait_for_rpc_to_be_available "{{.l1_rpc_url}}"
echo_ts "L1 RPC is now available"

# Fund accounts on L1.
echo_ts "Funding important accounts on l1"
fund_account_on_l1 "admin" "{{.zkevm_l2_admin_address}}"
fund_account_on_l1 "sequencer" "{{.zkevm_l2_sequencer_address}}"
fund_account_on_l1 "aggregator" "{{.zkevm_l2_aggregator_address}}"
fund_account_on_l1 "agglayer" "{{.zkevm_l2_agglayer_address}}"
fund_account_on_l1 "claimtxmanager" "{{.zkevm_l2_claimtxmanager_address}}"

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
jq --slurpfile c combined.json '.rollupCreationBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.rollupManagerCreationBlockNumber = $c[0].upgradeToULxLyBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.genesisBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config = {chainId:{{.l1_chain_id}}}' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonZkEVMGlobalExitRootAddress = $c[0].polygonZkEVMGlobalExitRootAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonRollupManagerAddress = $c[0].polygonRollupManagerAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polTokenAddress = $c[0].polTokenAddress' genesis.json > g.json; mv g.json genesis.json
jq --slurpfile c combined.json '.L1Config.polygonZkEVMAddress = $c[0].rollupAddress' genesis.json > g.json; mv g.json genesis.json

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

{{if .is_cdk_validium}}
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
{{end}}

# Grant the aggregator role to the agglayer so that it can also verify batches.
# cast keccak "TRUSTED_AGGREGATOR_ROLE"
echo_ts "Granting the aggregator role to the agglayer so that it can also verify batches"
cast send \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polygonRollupManagerAddress' combined.json)" \
    'grantRole(bytes32,address)' \
    "0x084e94f375e9d647f87f5b2ceffba1e062c70f6009fdbcf80291e803b5c9edd4" "{{.zkevm_l2_agglayer_address}}"

# The contract setup is done!
touch .init-complete.lock
