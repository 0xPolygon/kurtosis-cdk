#!/bin/bash
# This script is responsible for deploying the contracts for zkEVM/CDK.
global_log_level="{{.global_log_level}}"
if [[ $global_log_level == "debug" ]]; then
    set -x
fi

echo_ts() {
    green="\e[32m"
    end_color="\e[0m"

    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo -e "$green$timestamp$end_color $1" >&2
}

wait_for_rpc_to_be_available() {
    counter=0
    max_retries=20
    until cast send --rpc-url "{{.l1_rpc_url}}" --mnemonic "{{.l1_preallocated_mnemonic}}" --value 0 "{{.zkevm_l2_sequencer_address}}" &> /dev/null; do
        ((counter++))
        echo_ts "Can't send L1 transfers yet... Retrying ($counter)..."
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

deploy_rollup_manager() {
    # Deploy contracts.
    echo_ts "Step 1: Preparing testnet"
    npx hardhat run deployment/testnet/prepareTestnet.ts --network localhost 2>&1 | tee 01_prepare_testnet.out

    echo_ts "Step 2: Creating genesis"
    MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
    if [[ ! -e deployment/v2/genesis.json ]]; then
        echo_ts "The genesis file was not created after running createGenesis"
        exit 1
    fi

    echo_ts "Step 3: Deploying PolygonZKEVMDeployer"
    npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost 2>&1 | tee 03_zkevm_deployer.out

    echo_ts "Step 4: Deploying contracts"
    npx hardhat run deployment/v2/3_deployContracts.ts --network localhost 2>&1 | tee 04_deploy_contracts.out
    if [[ ! -e deployment/v2/deploy_output.json ]]; then
        echo_ts "The deploy_output.json file was not created after running deployContracts"
        exit 1
    fi
}


if [[ -e "/opt/zkevm/.init-complete{{.deployment_suffix}}.lock" ]]; then
    echo_ts "This script has already been executed"
    exit 1
fi

# If we had a genesis, and combined that were created outside of
# kurtosis entirely, we'll use those and exit. This is like a
# permissionless use case or a use case where we're starting from
# recovered network
if [[ -e "/opt/contract-deploy/genesis.json" && -e "/opt/contract-deploy/combined.json" ]]; then
    echo_ts "We have a genesis and combined output file from a previous deployment"
    cp /opt/contract-deploy/* /opt/zkevm/
    pushd /opt/zkevm || exit 1
    jq '.firstBatchData' combined.json > first-batch-config.json
    popd || exit 1
    exit
fi

echo_ts "Waiting for the L1 RPC to be available"
wait_for_rpc_to_be_available "{{.l1_rpc_url}}"
echo_ts "L1 RPC is now available"

echo_ts "Funding important accounts on L1"
fund_account_on_l1 "admin" "{{.zkevm_l2_admin_address}}"
fund_account_on_l1 "sequencer" "{{.zkevm_l2_sequencer_address}}"
fund_account_on_l1 "aggregator" "{{.zkevm_l2_aggregator_address}}"
fund_account_on_l1 "agglayer" "{{.zkevm_l2_agglayer_address}}"
fund_account_on_l1 "l1testing" "{{.zkevm_l2_l1testing_address}}"
fund_account_on_l1 "sovereignadmin" "{{.zkevm_l2_sovereignadmin_address}}"

echo_ts "Setting up local zkevm-contracts repo for deployment"
pushd /opt/zkevm-contracts || exit 1
cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
# Set up the hardhat environment.
sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts
# Set up a foundry project in case we do a gas token or dac deployment.
printf "[profile.default]\nsrc = 'contracts'\nout = 'out'\nlibs = ['node_modules']\n" > foundry.toml

# Deploy gas token
# shellcheck disable=SC1054,SC1072,SC1083
{{ if .gas_token_enabled }}
# shellcheck disable=SC1009,SC1073,SC1065,SC1050
{{ if or (eq .gas_token_address "0x0000000000000000000000000000000000000000") (eq .gas_token_address "") }}
echo_ts "Deploying gas token to L1"
forge create \
    --broadcast \
    --json \
    --rpc-url "{{.l1_rpc_url}}" \
    --mnemonic "{{.l1_preallocated_mnemonic}}" \
    contracts/mocks/ERC20PermitMock.sol:ERC20PermitMock \
    --constructor-args "CDK Gas Token" "CDK" "{{.zkevm_l2_admin_address}}" "1000000000000000000000000" \
    > gasToken-erc20.json
jq \
    --slurpfile c gasToken-erc20.json \
    '.gasTokenAddress = $c[0].deployedTo' \
    /opt/contract-deploy/create_rollup_parameters.json \
    > /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json

# shellcheck disable=SC1073,SC1009
{{ else }}
echo_ts "Using L1 pre-deployed gas token: {{ .gas_token_address }}"
jq \
    --arg c "{{ .gas_token_address }}" \
    '.gasTokenAddress = $c' \
    /opt/contract-deploy/create_rollup_parameters.json \
    > /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
{{ end }}
{{ end }}

is_first_rollup=0 # an indicator if this deployment is doing the first setup of the agglayer etc
if [[ ! -e /opt/zkevm/combined.json ]]; then
    echo_ts "It looks like this is the first rollup so we'll deploy the LxLy and Rollup Manager"
    deploy_rollup_manager
    is_first_rollup=1
else
    echo_ts "Skipping deployment of the Rollup Manager and LxLy"
    cp /opt/zkevm/genesis.json /opt/zkevm-contracts/deployment/v2/
    cp /opt/zkevm/deploy_output.json /opt/zkevm-contracts/deployment/v2/
fi

# Do not create another rollup in the case of an optimism rollup. This will be done in run-sovereign-setup.sh
deploy_optimism_rollup="{{.deploy_optimism_rollup}}"
if [[ "$deploy_optimism_rollup" != "true" ]]; then
    echo_ts "Step 5: Creating Rollup/Validium"
    npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee 05_create_rollup.out
    # Support for new output file format
    if [[ $(echo deployment/v2/create_rollup_output_* | wc -w) -gt 1 ]]; then
        echo_ts "There are multiple create rollup output files. We don't know how to handle this situation"
        exit 1
    fi
    if [[ $(echo deployment/v2/create_rollup_output_* | wc -w) -eq 1 ]]; then
        mv deployment/v2/create_rollup_output_* deployment/v2/create_rollup_output.json
    fi
    if [[ ! -e deployment/v2/create_rollup_output.json ]]; then
        echo_ts "The create_rollup_output.json file was not created after running createRollup"
        exit 1
    fi
fi

# Combine contract deploy files.
# At this point, all of the contracts /should/ have been deployed.
# Now we can combine all of the files and put them into the general zkevm folder.
echo_ts "Combining contract deploy files"
mkdir -p /opt/zkevm
cp /opt/zkevm-contracts/deployment/v2/deploy_*.json /opt/zkevm/
cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
# Check create_rollup_output.json exists before copying it.
# For the case of deploy_optimism_rollup, create_rollup_output.json will not be created.
if [[ -e /opt/zkevm-contracts/deployment/v2/create_rollup_output.json ]]; then
    cp /opt/zkevm-contracts/deployment/v2/create_rollup_output.json /opt/zkevm/
else
    echo "File /opt/zkevm-contracts/deployment/v2/create_rollup_output.json does not exist."
fi
cp /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json /opt/zkevm/
popd || exit 1

echo_ts "Creating combined.json"
pushd /opt/zkevm/ || exit 1

cp genesis.json genesis.original.json
# Check create_rollup_output.json exists before copying it.
# For the case of deploy_optimism_rollup, create_rollup_output.json will not be created.
if [[ -e create_rollup_output.json ]]; then
    jq --slurpfile rollup create_rollup_output.json '. + $rollup[0]' deploy_output.json > combined.json
else
    echo "File create_rollup_output.json does not exist. Copying deploy_output.json to combined.json."
    cp deploy_output.json combined.json
fi
jq '.polygonZkEVML2BridgeAddress = .polygonZkEVMBridgeAddress' combined.json > c.json; mv c.json combined.json

# Add the L2 GER Proxy address in combined.json (for panoptichain).
zkevm_global_exit_root_l2_address=$(jq -r '.genesis[] | select(.contractName == "PolygonZkEVMGlobalExitRootL2 proxy") | .address' /opt/zkevm/genesis.json)
jq --arg a "$zkevm_global_exit_root_l2_address" '.polygonZkEVMGlobalExitRootL2Address = $a' combined.json > c.json; mv c.json combined.json

{{ if .gas_token_enabled }}
jq --slurpfile cru /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json '.gasTokenAddress = $cru[0].gasTokenAddress' combined.json > c.json; mv c.json combined.json
{{ end }}


# There are a bunch of fields that need to be renamed in order for the
# older fork7 code to be compatible with some of the fork8
# automations. This schema matching can be dropped once this is
# versioned up to 8
# DEPRECATED we will likely remove support for anything before fork 9 soon
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
jq --slurpfile c combined.json '.bridgeGenBlockNumber = $c[0].createRollupBlockNumber' combined.json > c.json; mv c.json combined.json

echo_ts "Final combined.json is ready:"
cp combined.json "combined{{.deployment_suffix}}.json"
cat combined.json

# This is a jq script to transform the CDK-style genesis file into an allocs file for erigon
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
if ! output_json=$(jq "$jq_script" /opt/zkevm/genesis.json); then
    echo_ts "Error processing JSON with jq"
    exit 1
fi

# Write the output JSON to a file
if ! echo "$output_json" | jq . > "dynamic-{{.chain_name}}-allocs.json"; then
    echo_ts "Error writing to file dynamic-{{.chain_name}}-allocs.json"
    exit 1
fi

echo_ts "Transformation complete. Output written to dynamic-{{.chain_name}}-allocs.json"
if [[ -e create_rollup_output.json ]]; then
    jq '{"root": .root, "timestamp": 0, "gasLimit": 0, "difficulty": 0}' /opt/zkevm/genesis.json > "dynamic-{{.chain_name}}-conf.json"
    batch_timestamp=$(jq '.firstBatchData.timestamp' combined.json)
    jq --arg bt "$batch_timestamp" '.timestamp |= ($bt | tonumber)' "dynamic-{{.chain_name}}-conf.json" > tmp_output.json
    mv tmp_output.json "dynamic-{{.chain_name}}-conf.json"
else
    echo "Without create_rollup_output.json, there is no batch_timestamp available"
    jq '{"root": .root, "timestamp": 0, "gasLimit": 0, "difficulty": 0}' /opt/zkevm/genesis.json > "dynamic-{{.chain_name}}-conf.json"
fi

# zkevm.initial-batch.config
jq '.firstBatchData' combined.json > first-batch-config.json

if [[ ! -s "dynamic-{{.chain_name}}-conf.json" ]]; then
    echo_ts "Error creating the dynamic kurtosis config"
    exit 1
fi

# Configure contracts.

if [[ $is_first_rollup -eq 1 ]]; then
    # Grant the aggregator role to the agglayer so that it can also verify batches.
    # cast keccak "TRUSTED_AGGREGATOR_ROLE"
    echo_ts "Granting the aggregator role to the agglayer so that it can also verify batches"
    cast send \
         --private-key "{{.zkevm_l2_admin_private_key}}" \
         --rpc-url "{{.l1_rpc_url}}" \
         "$(jq -r '.polygonRollupManagerAddress' combined.json)" \
         'grantRole(bytes32,address)' \
         "0x084e94f375e9d647f87f5b2ceffba1e062c70f6009fdbcf80291e803b5c9edd4" "{{.zkevm_l2_agglayer_address}}"
fi

# The sequencer needs to pay POL when it sequences batches.
# This gets refunded when the batches are verified on L1.
# In order for this to work t,he rollup address must be approved to transfer the sequencers' POL tokens.
echo_ts "Minting POL token on L1 for the sequencer"
cast send \
    --private-key "{{.zkevm_l2_sequencer_private_key}}" \
    --legacy \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polTokenAddress' combined.json)" \
    'mint(address,uint256)' \
    "{{.zkevm_l2_sequencer_address}}" 1000000000000000000000000000

echo_ts "Approving the rollup address to transfer POL tokens on behalf of the sequencer"
cast send \
    --private-key "{{.zkevm_l2_sequencer_private_key}}" \
    --legacy \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polTokenAddress' combined.json)" \
    'approve(address,uint256)(bool)' \
    "$(jq -r '.rollupAddress' combined.json)" 1000000000000000000000000000

# {{if .is_cdk_validium}}
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
# {{end}}

# Deploy deterministic proxy.
# https://github.com/Arachnid/deterministic-deployment-proxy
# You can find the `signer_address`, `transaction` and `deployer_address` by looking at the README.
echo_ts "Deploying deterministic deployment proxy"
signer_address="0x3fab184622dc19b6109349b94811493bf2a45362"
transaction="0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222"
deployer_address="0x4e59b44847b379578588920ca78fbf26c0b4956c"
cast send \
    --rpc-url "{{.l1_rpc_url}}" \
    --mnemonic "{{.l1_preallocated_mnemonic}}" \
    --value "0.01ether" \
    "$signer_address"
cast publish --rpc-url "{{.l1_rpc_url}}" "$transaction"
if [[ $(cast code --rpc-url "{{.l1_rpc_url}}" $deployer_address) == "0x" ]]; then
    echo_ts "No code at deployer address: $deployer_address"
    exit 1
fi


# If we've configured the l1 network with the minimal preset, we
# should probably wait for the first finalized block. This isn't
# strictly specific to minimal preset, but if we don't have "minimal"
# configured, it's going to take like 25 minutes for the first
# finalized block
l1_preset="{{.l1_preset}}"
if [[ $l1_preset == "minimal" ]]; then
    # This might not be required, but it seems like the downstream
    # processes are more reliable if we wait for all of the deployments to
    # finalize before moving on
    current_block_number="$(cast block-number --rpc-url '{{.l1_rpc_url}}')"
    finalized_block_number=0
    until [[ $finalized_block_number -gt $current_block_number ]]; do
        sleep 5
        finalized_block_number="$(cast block-number --rpc-url '{{.l1_rpc_url}}' finalized)"
    done
fi

# The contract setup is done!
touch "/opt/zkevm/.init-complete{{.deployment_suffix}}.lock"
