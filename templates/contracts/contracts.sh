#!/bin/bash
input_dir="/opt/input"
output_dir="/opt/output"
keystores_dir="/opt/keystores"

# Internal function
_create_geth_keystore() {
    local keystore_name="$1"
    local private_key="$2"
    local password="$3"

    temp_dir="/tmp/$keystore_name"
    mkdir -p "$temp_dir"
    cast wallet import --keystore-dir "$temp_dir" --private-key "$private_key" --unsafe-password "$password" "$keystore_name"
    jq < "$temp_dir/$keystore_name" > "$keystores_dir/$keystore_name"
    chmod a+r "$keystores_dir/$keystore_name"
    rm -rf "$temp_dir"
}

# Internal function
_echo_ts() {
    green="\e[32m"
    end_color="\e[0m"

    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo -e "$green$timestamp$end_color $1" >&2
}

# Internal function, used by deploy_agglayer_core_contracts
_wait_for_rpc_to_be_available() {
    local rpc_url="$1"
    local mnemonic="$2"

    counter=0
    max_retries=20
    until cast send --rpc-url "$rpc_url" --mnemonic "$mnemonic" --value 0 "{{.zkevm_l2_sequencer_address}}" &> /dev/null; do
        ((counter++))
        _echo_ts "Can't send L1 transfers yet... Retrying ($counter)..."
        if [[ $counter -ge $max_retries ]]; then
            _echo_ts "Exceeded maximum retry attempts. Exiting."
            exit 1
        fi
        sleep 5
    done
}

# Internal function, used by deploy_agglayer_core_contracts
_fund_account_on_l1() {
    name="$1"
    address="$2"
    _echo_ts "Funding $name account"
    cast send \
        --rpc-url "{{.l1_rpc_url}}" \
        --mnemonic "{{.l1_preallocated_mnemonic}}" \
        --value "{{.l1_funding_amount}}" \
        "$address"
}

# Internal function, used by deploy_agglayer_core_contracts
_deploy_rollup_manager() {
    # Deploy contracts.
    _echo_ts "Step 1: Preparing testnet"
    npx hardhat run deployment/testnet/prepareTestnet.ts --network localhost 2>&1 | tee 01_prepare_testnet.out

    _echo_ts "Step 2: Deploying PolygonZKEVMDeployer"
    npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network localhost 2>&1 | tee 03_zkevm_deployer.out

    _echo_ts "Step 3: Deploying contracts"
    npx hardhat run deployment/v2/3_deployContracts.ts --network localhost 2>&1 | tee 04_deploy_contracts.out
    if [[ ! -e deployment/v2/deploy_output.json ]]; then
        _echo_ts "The deploy_output.json file was not created after running deployContracts"
        exit 1
    fi
}

# Always called by the contracts service
create_keystores() {
    _create_geth_keystore "sequencer.keystore"       "{{.zkevm_l2_sequencer_private_key}}"       "{{.zkevm_l2_keystore_password}}"
    _create_geth_keystore "aggregator.keystore"      "{{.zkevm_l2_aggregator_private_key}}"      "{{.zkevm_l2_keystore_password}}"
    _create_geth_keystore "claimtxmanager.keystore"  "{{.zkevm_l2_claimtxmanager_private_key}}"  "{{.zkevm_l2_keystore_password}}"
    _create_geth_keystore "agglayer.keystore"        "{{.zkevm_l2_agglayer_private_key}}"        "{{.zkevm_l2_keystore_password}}"
    _create_geth_keystore "dac.keystore"             "{{.zkevm_l2_dac_private_key}}"             "{{.zkevm_l2_keystore_password}}"
    _create_geth_keystore "proofsigner.keystore"     "{{.zkevm_l2_proofsigner_private_key}}"     "{{.zkevm_l2_keystore_password}}"
    _create_geth_keystore "aggoracle.keystore"       "{{.zkevm_l2_aggoracle_private_key}}"       "{{.zkevm_l2_keystore_password}}"
    _create_geth_keystore "sovereignadmin.keystore"  "{{.zkevm_l2_sovereignadmin_private_key}}"  "{{.zkevm_l2_keystore_password}}"
    _create_geth_keystore "claimsponsor.keystore"    "{{.zkevm_l2_claimsponsor_private_key}}"    "{{.zkevm_l2_keystore_password}}"

    # Generate multiple aggoracle keystores for committee members
    # shellcheck disable=SC2050
    if [[ "{{ .use_agg_oracle_committee }}" == "true" ]]; then
        MNEMONIC="lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop"
        COMMITTEE_SIZE="{{ .agg_oracle_committee_total_members }}"

        if [[ "$COMMITTEE_SIZE" -ge 1 ]]; then
            for (( index=0; index<COMMITTEE_SIZE; index++ )); do
                aggoracle_private_key=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index $index)
                _create_geth_keystore "aggoracle-$index.keystore" "$aggoracle_private_key" "{{.zkevm_l2_keystore_password}}"
            done
        fi
    fi

    # Generate multiple aggsender validator keystores for validators
    # shellcheck disable=SC2050
    if [[ "{{ .use_agg_sender_validator }}" == "true" ]]; then
        MNEMONIC="lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop"
        VALIDATOR_COUNT="{{ .agg_sender_validator_total_number }}"

        if [[ "$VALIDATOR_COUNT" -ge 1 ]]; then
            json_output="["

            # For loop starts from 1 instead of 0 for aggsender-validator service suffix consistency
            for (( index=2; index<VALIDATOR_COUNT+1; index++ )); do
                # $((index + 100)) is being used instead of $index, because we are using the same MNEMONIC for multiple different addresses.
                # By adding 100 to the original index, we are adding variety in the addresses being generated.
                aggsendervalidator_private_key=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index $((index + 100)))
                aggsender_validator_address=$(cast wallet address --private-key "$aggsendervalidator_private_key")

                _create_geth_keystore "aggsendervalidator-$index.keystore" "$aggsendervalidator_private_key" "{{.zkevm_l2_keystore_password}}"

                json_output+='{"index":'$index',"address":"'$aggsender_validator_address'","private_key":"'$aggsendervalidator_private_key'"}'
                if [[ $index -lt $VALIDATOR_COUNT ]]; then
                    json_output+=","
                fi
            done

            json_output+="]"

            echo "$json_output" > "$output_dir"/aggsender-validators.json

            jq --argfile vals "$output_dir"/aggsender-validators.json '
                .aggchainParams.signers += (
                    $vals
                    | to_entries
                    | map([ 
                        .value.address, 
                        if .value.index == 0 then 
                            "http://aggkit{{ .deployment_suffix }}-aggsender-validator:{{ .aggsender_validator_grpc_port }}" 
                        else 
                            "http://aggkit{{ .deployment_suffix }}-aggsender-validator-\(.value.index | tostring | if length == 1 then "00" + . else if length == 2 then "0" + . else . end end):{{ .aggsender_validator_grpc_port }}" 
                        end 
                    ])
                )
            ' "$input_dir"/create_new_rollup.json > "$input_dir"/create_new_rollup.json.tmp && \
            mv "$input_dir"/create_new_rollup.json.tmp "$input_dir"/create_new_rollup.json
        fi
    fi
}

# Called if l1_custom_genesis and consensus_contract_type is pessimistic
configure_contract_container_custom_genesis() {
    cp "$input_dir"/op-custom-genesis-addresses.json /opt/zkevm/combined.json

    sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' /opt/zkevm-contracts/hardhat.config.ts
    cp "$input_dir"/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json

    pushd /opt/zkevm-contracts || exit 1
    MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
    popd || exit 1

    cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
    cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm/
    cp /opt/zkevm/combined.json /opt/zkevm/combined-001.json

    global_exit_root_address=$(jq -r '.polygonZkEVMGlobalExitRootAddress' /opt/zkevm/combined.json)
    cast send "$global_exit_root_address" "initialize()" --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}"
}

# Calles if l1_custom_genesis and consensus_contract_type is rollup or cdk_validium
configure_contract_container_custom_genesis_cdk_erigon() {
    # deploymentRollupManagerBlockNumber field inside cdk-erigon-custom-genesis-addresses.json must be different to 0 because cdk-erigon and cdk-node requires this value (zkevm.l1-first-block) to be different to 0
    cp "$input_dir"/cdk-erigon-custom-genesis-addresses.json /opt/zkevm/combined.json

    cp /opt/zkevm/combined.json /opt/zkevm-contracts/deployment/v2/deploy_output.json
    cp /opt/zkevm/combined.json /opt/zkevm/deploy_output.json

    global_exit_root_address=$(jq -r '.polygonZkEVMGlobalExitRootAddress' /opt/zkevm/combined.json)
    cast send "$global_exit_root_address" "initialize()" --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}"
}

# Called when no l1 custom genesis
deploy_agglayer_core_contracts() {
    # This script is responsible for deploying the contracts for zkEVM/CDK.
    global_log_level="{{.global_log_level}}"
    if [[ $global_log_level == "debug" ]]; then
        set -x
    fi

    if [[ -e "/opt/zkevm/.init-complete{{.deployment_suffix}}.lock" ]]; then
        _echo_ts "This script has already been executed"
        exit 1
    fi

    # If we had a genesis, and combined that were created outside of
    # kurtosis entirely, we'll use those and exit. This is like a
    # permissionless use case or a use case where we're starting from
    # recovered network
    if [[ -e "/opt/contract-deploy/genesis.json" && -e "/opt/contract-deploy/combined.json" ]]; then
        _echo_ts "We have a genesis and combined output file from a previous deployment"
        cp /opt/contract-deploy/* /opt/zkevm/
        pushd /opt/zkevm || exit 1
        jq '.firstBatchData' combined.json > first-batch-config.json
        popd || exit 1
        exit
    fi

    _echo_ts "Waiting for the L1 RPC to be available"
    _wait_for_rpc_to_be_available "{{.l1_rpc_url}}" "{{.l1_preallocated_mnemonic}}"
    _echo_ts "L1 RPC is now available"

    _echo_ts "Funding important accounts on L1"
    _fund_account_on_l1 "admin" "{{.zkevm_l2_admin_address}}"
    _fund_account_on_l1 "sequencer" "{{.zkevm_l2_sequencer_address}}"
    _fund_account_on_l1 "aggregator" "{{.zkevm_l2_aggregator_address}}"
    _fund_account_on_l1 "agglayer" "{{.zkevm_l2_agglayer_address}}"
    _fund_account_on_l1 "l1testing" "{{.zkevm_l2_l1testing_address}}"
    _fund_account_on_l1 "sovereignadmin" "{{.zkevm_l2_sovereignadmin_address}}"

    _echo_ts "Setting up local zkevm-contracts repo for deployment"
    pushd /opt/zkevm-contracts || exit 1
    cp "$input_dir"/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json
    cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm-contracts/deployment/v2/create_rollup_parameters.json
    # Set up the hardhat environment.
    sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts
    # Set up a foundry project in case we do a gas token or dac deployment.
    printf "[profile.default]\nsrc = 'contracts'\nout = 'out'\nlibs = ['node_modules']\n" > foundry.toml

    is_first_rollup=0 # an indicator if this deployment is doing the first setup of the agglayer etc
    if [[ ! -e /opt/zkevm/combined.json ]]; then
        _echo_ts "It looks like this is the first rollup so we'll deploy the LxLy and Rollup Manager"
        _deploy_rollup_manager
        is_first_rollup=1
    else
        _echo_ts "Skipping deployment of the Rollup Manager and LxLy"
        cp /opt/zkevm/deploy_output.json /opt/zkevm-contracts/deployment/v2/
    fi

    # Combine contract deploy files.
    # At this point, all of the contracts /should/ have been deployed.
    # Now we can combine all of the files and put them into the general zkevm folder.
    _echo_ts "Combining contract deploy files"
    mkdir -p /opt/zkevm
    cp /opt/zkevm-contracts/deployment/v2/deploy_*.json /opt/zkevm/

    popd || exit 1

    _echo_ts "Creating combined.json"
    pushd /opt/zkevm/ || exit 1
    cp deploy_output.json combined.json
    cat combined.json

    # There are a bunch of fields that need to be renamed in order for the
    # older fork7 code to be compatible with some of the fork8
    # automations. This schema matching can be dropped once this is
    # versioned up to 8
    # DEPRECATED we will likely remove support for anything before fork 9 soon
    fork_id="{{.zkevm_rollup_fork_id}}"
    if [[ $fork_id -lt 8 && $fork_id -ne 0 ]]; then
        jq '.polygonRollupManagerAddress = .polygonRollupManager' combined.json > c.json; mv c.json combined.json
        jq '.deploymentRollupManagerBlockNumber = .deploymentBlockNumber' combined.json > c.json; mv c.json combined.json
        jq '.upgradeToULxLyBlockNumber = .deploymentBlockNumber' combined.json > c.json; mv c.json combined.json
        jq '.polygonDataCommitteeAddress = .polygonDataCommittee' combined.json > c.json; mv c.json combined.json
    fi

    # Configure contracts.

    if [[ $is_first_rollup -eq 1 ]]; then
        # Grant the aggregator role to the agglayer so that it can also verify batches.
        # cast keccak "TRUSTED_AGGREGATOR_ROLE"
        _echo_ts "Granting the aggregator role to the agglayer so that it can also verify batches"
        cast send \
            --private-key "{{.zkevm_l2_admin_private_key}}" \
            --rpc-url "{{.l1_rpc_url}}" \
            "$(jq -r '.polygonRollupManagerAddress' combined.json)" \
            'grantRole(bytes32,address)' \
            "0x084e94f375e9d647f87f5b2ceffba1e062c70f6009fdbcf80291e803b5c9edd4" "{{.zkevm_l2_agglayer_address}}"
    fi

    # The sequencer needs to pay POL when it sequences batches.
    # This gets refunded when the batches are verified on L1.
    # In order for this to work the rollup address must be approved to transfer the sequencers' POL tokens.
    _echo_ts "Minting POL token on L1 for the sequencer"
    cast send \
        --private-key "{{.zkevm_l2_sequencer_private_key}}" \
        --legacy \
        --rpc-url "{{.l1_rpc_url}}" \
        "$(jq -r '.polTokenAddress' combined.json)" \
        'mint(address,uint256)' \
        "{{.zkevm_l2_sequencer_address}}" 1000000000000000000000000000

    # Deploy deterministic proxy.
    # https://github.com/Arachnid/deterministic-deployment-proxy
    # You can find the `signer_address`, `transaction` and `deployer_address` by looking at the README.
    _echo_ts "Deploying deterministic deployment proxy"
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
        _echo_ts "No code at deployer address: $deployer_address"
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
}

# main handler, execute function according to parameter received
if [[ "$1" == "create_keystores" ]]; then
    create_keystores
elif [[ "$1" == "configure_contract_container_custom_genesis" ]]; then
    configure_contract_container_custom_genesis
elif [[ "$1" == "configure_contract_container_custom_genesis_cdk_erigon" ]]; then
    configure_contract_container_custom_genesis_cdk_erigon
elif [[ "$1" == "deploy_agglayer_core_contracts" ]]; then
    deploy_agglayer_core_contracts
else
    echo "Invalid argument: $1"
    exit 1
fi
