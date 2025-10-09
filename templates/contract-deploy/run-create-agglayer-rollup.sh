#!/bin/bash

input_dir="/opt/input"


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

create_genesis() {
    echo_ts "Step 4: Creating genesis"
    pushd /opt/zkevm-contracts || exit 1
    MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
    if [[ ! -e deployment/v2/genesis.json ]]; then
        echo_ts "The genesis file was not created after running createGenesis"
        exit 1
    fi
    popd || exit 1
}

echo_ts "Waiting for the L1 RPC to be available"
wait_for_rpc_to_be_available "{{.l1_rpc_url}}"
echo_ts "L1 RPC is now available"

cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json
# shellcheck disable=SC1054,SC1072,SC1083
{{ if eq .consensus_contract_type "ecdsa_multisig" }}
cp "$input_dir"/create_new_rollup.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
# shellcheck disable=SC1073,1009
{{ else }}
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
{{ end }}

create_genesis

echo_ts "Setting up local zkevm-contracts repo for deployment"
pushd /opt/zkevm-contracts || exit 1
# Set up the hardhat environment. It needs to be executed even in custom genesis mode
sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts

# Deploy gas token
# shellcheck disable=SC1054,SC1072,SC1083
{{ if .gas_token_enabled }}
    {{ if or (eq .gas_token_address "0x0000000000000000000000000000000000000000") (eq .gas_token_address "") }}
    echo_ts "Deploying gas token to L1"
        {{ if eq .consensus_contract_type "ecdsa_multisig" }}
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
            '.gasTokenAddress = $c[0].deployedTo | .sovereignParams.sovereignWETHAddress = $c[0].deployedTo' \
            "$input_dir"/create_new_rollup.json \
            > /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
        {{ else }}
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
        {{ end }}
    {{ else }}
    echo_ts "Using L1 pre-deployed gas token: {{ .gas_token_address }}"
        {{ if eq .consensus_contract_type "ecdsa_multisig" }}
        jq \
            --arg c "{{ .gas_token_address }}" \
            '.gasTokenAddress = $c' \
            "$input_dir"/create_new_rollup.json \
            > /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
        {{ else }}
        jq \
            --arg c "{{ .gas_token_address }}" \
            '.gasTokenAddress = $c' \
            /opt/contract-deploy/create_rollup_parameters.json \
            > /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
        {{ end }}
    {{ end }}
{{ end }}

cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/

{{ if eq .consensus_contract_type "ecdsa_multisig" }}
# Set gasTokenAddress and sovereignWETHAddress to zero address if they have "<no value>"
jq 'walk(if type == "object" then 
        with_entries(
            if .key == "gasTokenAddress" and (.value == "<no value>" || .value == "") then 
                .value = "0x0000000000000000000000000000000000000000" 
            elif .key == "sovereignWETHAddress" and (.value == "<no value>" || .value == "") then 
                .value = "0x0000000000000000000000000000000000000000"
            else 
                . 
            end
        ) 
    else 
        . 
    end)' \
    /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json > temp.json && \
    mv temp.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
{{ end }}

# Comment out aggLayerGateway.addDefaultAggchainVKey for additional rollups with same AggchainVKeySelector and OwnedAggchainVKey
if [[ "{{ .zkevm_rollup_id }}" != "1" ]]; then
sed -i '/await aggLayerGateway\.addDefaultAggchainVKey(/,/);/s/^/\/\/ /' /opt/zkevm-contracts/deployment/v2/4_createRollup.ts
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

# Check create_rollup_output.json exists before copying it.
# For the case of deploy_optimism_rollup, create_rollup_output.json will not be created.
if [[ -e /opt/zkevm-contracts/deployment/v2/create_rollup_output.json ]]; then
    cp /opt/zkevm-contracts/deployment/v2/create_rollup_output.json /opt/zkevm/
else
    echo "File /opt/zkevm-contracts/deployment/v2/create_rollup_output.json does not exist."
fi
cp /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json /opt/zkevm/
popd || exit 1

echo_ts "Modifying combined.json"
pushd /opt/zkevm/ || exit 1

cp genesis.json genesis.original.json
# Check create_rollup_output.json exists before copying it.
# For the case of deploy_optimism_rollup, create_rollup_output.json will not be created.
if [[ -e create_rollup_output.json ]]; then
    echo "File create_rollup_output.json exists. Combining files..."
    jq --slurpfile rollup create_rollup_output.json '. + $rollup[0]' deploy_output.json > combined.json
else
    echo "File create_rollup_output.json does not exist. Trying to copy deploy_output.json to combined.json."
    cp deploy_output.json combined.json
fi
jq '.polygonZkEVML2BridgeAddress = .polygonZkEVMBridgeAddress' combined.json > c.json; mv c.json combined.json

# Add the L2 GER Proxy address in combined.json (for panoptichain).
zkevm_global_exit_root_l2_address=$(jq -r '.genesis[] | select(.contractName == "PolygonZkEVMGlobalExitRootL2 proxy") | .address' /opt/zkevm/genesis.json)
jq --arg a "$zkevm_global_exit_root_l2_address" '.polygonZkEVMGlobalExitRootL2Address = $a' combined.json > c.json; mv c.json combined.json

{{ if .gas_token_enabled }}
jq --slurpfile cru /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json '.gasTokenAddress = $cru[0].gasTokenAddress' combined.json > c.json; mv c.json combined.json

gas_token_address=$(jq -r '.gasTokenAddress' /opt/zkevm/combined.json)
l1_bridge_addr=$(jq -r '.polygonZkEVMBridgeAddress' /opt/zkevm/combined.json)
# Bridge gas token to L2 to prevent bridge underflow reverts
echo "Bridging initial gas token to L2 to prevent bridge underflow reverts..."
polycli ulxly bridge asset \
    --bridge-address "$l1_bridge_addr" \
    --destination-address "0x0000000000000000000000000000000000000000" \
    --destination-network "{{.zkevm_rollup_id}}" \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --rpc-url "{{.l1_rpc_url}}" \
    --value 10000000000000000000000 \
    --token-address $gas_token_address
{{ end }}


# There are a bunch of fields that need to be renamed in order for the
# older fork7 code to be compatible with some of the fork8
# automations. This schema matching can be dropped once this is
# versioned up to 8
# DEPRECATED we will likely remove support for anything before fork 9 soon
fork_id="{{.zkevm_rollup_fork_id}}"
if [[ $fork_id -lt 8 && $fork_id -ne 0 ]]; then
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

echo_ts "Approving the rollup address to transfer POL tokens on behalf of the sequencer"
cast send \
    --private-key "{{.zkevm_l2_sequencer_private_key}}" \
    --legacy \
    --rpc-url "{{.l1_rpc_url}}" \
    "$(jq -r '.polTokenAddress' combined.json)" \
    'approve(address,uint256)(bool)' \
    "$(jq -r '.rollupAddress' combined.json)" 1000000000000000000000000000

{{ if ne .consensus_contract_type "ecdsa_multisig" }}
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
{{ end }}


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
