#!/bin/bash
scripts_dir="{{.scripts_dir}}"
input_dir="{{.input_dir}}"
output_dir="{{.output_dir}}"
keystores_dir="{{.keystores_dir}}"
contracts_dir="{{.contracts_dir}}"

# Compatibility with the old zkevm folder for e2e tests while we are adapting them.
if [[ ! -e /opt/zkevm ]]; then
    ln -s "$output_dir" /opt/zkevm
fi

# Let's rename zkevm-contracts to agglayer-contracts if that's not already done
if [[ -e /opt/zkevm-contracts && ! -e "$contracts_dir" ]]; then
    mv /opt/zkevm-contracts "$contracts_dir"
    ln -s "$contracts_dir" /opt/zkevm-contracts
fi

# Internal function, used by create_keystores
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

# Internal function, used by deploy_agglayer_core_contracts and create_agglayer_rollup
_echo_ts() {
    green="\e[32m"
    end_color="\e[0m"

    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo -e "$green$timestamp$end_color $1" >&2
}

# Internal function, used by deploy_agglayer_core_contracts and create_agglayer_rollup
_wait_for_rpc_to_be_available() {
    local rpc_url="$1"
    local mnemonic="$2"

    counter=0
    max_retries=20
    until cast send --rpc-url "$rpc_url" --mnemonic "$mnemonic" --value 0 "{{.l2_sequencer_address}}" &> /dev/null; do
        ((counter++))
        _echo_ts "Can't send L1 transfers yet... Retrying ($counter)..."
        if [[ $counter -ge $max_retries ]]; then
            _echo_ts "Exceeded maximum retry attempts. Exiting."
            exit 1
        fi
        sleep 5
    done
}

# Internal function, used by create_agglayer_rollup
_create_genesis() {
    _echo_ts "Step 4: Creating genesis"
    pushd "$contracts_dir" || exit 1
    MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
    if [[ ! -e deployment/v2/genesis.json ]]; then
        _echo_ts "The genesis file was not created after running createGenesis"
        exit 1
    fi
    popd || exit 1
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
_deploy_agglayer_manager() {
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
    else
        # jq  \
        # '
        #     .AgglayerManager = .polygonRollupManagerAddress | del(.polygonRollupManagerAddress) |
        #     .AgglayerBridge = .polygonZkEVMBridgeAddress | del(.polygonZkEVMBridgeAddress) |
        #     .AgglayerGER = .polygonZkEVMGlobalExitRootAddress | del(.polygonZkEVMGlobalExitRootAddress) |
        #     .AgglayerGateway = .aggLayerGatewayAddress | del(.aggLayerGatewayAddress)
        # ' \
        # deployment/v2/deploy_output.json > deployment/v2/deploy_output.json.tmp \
        # && mv deployment/v2/deploy_output.json deployment/v2/deploy_output.json.original \
        # && mv deployment/v2/deploy_output.json.tmp deployment/v2/deploy_output.json

        # Contract's tools required OLD names as input... so we can't remove old fields.
        jq  \
        '
            .AgglayerManager = .polygonRollupManagerAddress|
            .AgglayerBridge = .polygonZkEVMBridgeAddress |
            .AgglayerGER = .polygonZkEVMGlobalExitRootAddress |
            .AgglayerGateway = .aggLayerGatewayAddress
        ' \
        deployment/v2/deploy_output.json > deployment/v2/deploy_output.json.tmp \
        && mv deployment/v2/deploy_output.json deployment/v2/deploy_output.json.original \
        && mv deployment/v2/deploy_output.json.tmp deployment/v2/deploy_output.json
        _echo_ts "Got a deploy_output.json file"
        cat deployment/v2/deploy_output.json
    fi
}

# Internal function, useb by initialize_rollup
_extract_addresses() {
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


# Always called by the contracts service
create_keystores() {
    _echo_ts "Executing function create_keystores"

    _create_geth_keystore "sequencer.keystore"       "{{.l2_sequencer_private_key}}"       "{{.l2_keystore_password}}"
    _create_geth_keystore "aggregator.keystore"      "{{.l2_aggregator_private_key}}"      "{{.l2_keystore_password}}"
    _create_geth_keystore "dac.keystore"             "{{.l2_dac_private_key}}"             "{{.l2_keystore_password}}"
    _create_geth_keystore "aggoracle.keystore"       "{{.l2_aggoracle_private_key}}"       "{{.l2_keystore_password}}"
    _create_geth_keystore "sovereignadmin.keystore"  "{{.l2_sovereignadmin_private_key}}"  "{{.l2_keystore_password}}"
    _create_geth_keystore "claimsponsor.keystore"    "{{.l2_claimsponsor_private_key}}"    "{{.l2_keystore_password}}"

    # Generate multiple aggoracle keystores for committee members
    # shellcheck disable=SC2050
    if [[ "{{ .use_agg_oracle_committee }}" == "true" ]]; then
        MNEMONIC="lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop"
        COMMITTEE_SIZE="{{ .agg_oracle_committee_total_members }}"

        if [[ "$COMMITTEE_SIZE" -ge 1 ]]; then
            for (( index=0; index<COMMITTEE_SIZE; index++ )); do
                aggoracle_private_key=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index $index)
                _create_geth_keystore "aggoracle-$index.keystore" "$aggoracle_private_key" "{{.l2_keystore_password}}"
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

                _create_geth_keystore "aggsendervalidator-$index.keystore" "$aggsendervalidator_private_key" "{{.l2_keystore_password}}"

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
    _echo_ts "Executing function configure_contract_container_custom_genesis"

    cp "$input_dir"/op-custom-genesis-addresses.json "$output_dir"/combined.json

    sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' "$contracts_dir"/hardhat.config.ts
    cp "$input_dir"/deploy_parameters.json "$contracts_dir"/deployment/v2/deploy_parameters.json

    pushd "$contracts_dir" || exit 1
    MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
    popd || exit 1

    cp "$contracts_dir"/deployment/v2/genesis.json "$output_dir"/
    cp "$input_dir"/create_rollup_parameters.json "$output_dir"/
    cp "$output_dir"/combined.json "$output_dir"/combined-001.json

    agglayer_ger=$(jq -r '.AgglayerGER' "$output_dir"/combined.json)
    cast send "$agglayer_ger" "initialize()" --private-key "{{.l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}"
}

# Called if l1_custom_genesis and consensus_contract_type is rollup or cdk-validium
configure_contract_container_custom_genesis_cdk_erigon() {
    _echo_ts "Executing function configure_contract_container_custom_genesis_cdk_erigon"

    # deploymentRollupManagerBlockNumber field inside cdk-erigon-custom-genesis-addresses.json must be different to 0 because cdk-erigon and cdk-node requires this value (zkevm.l1-first-block) to be different to 0
    cp "$input_dir"/cdk-erigon-custom-genesis-addresses.json "$output_dir"/combined.json

    cp "$output_dir"/combined.json "$contracts_dir"/deployment/v2/deploy_output.json
    cp "$output_dir"/combined.json "$output_dir"/deploy_output.json

    agglayer_ger=$(jq -r '.AgglayerGER' "$output_dir"/combined.json)
    cast send "$agglayer_ger" "initialize()" --private-key "{{.l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}"
}

# Called when no l1 custom genesis
deploy_agglayer_core_contracts() {
    _echo_ts "Executing function deploy_agglayer_core_contracts"

    # This script is responsible for deploying the contracts for zkEVM/CDK.
    global_log_level="{{.global_log_level}}"
    if [[ $global_log_level == "debug" ]]; then
        set -x
    fi

    if [[ -e "${output_dir}/.init-complete{{.deployment_suffix}}.lock" ]]; then
        _echo_ts "This script has already been executed"
        exit 1
    fi

    # If we had a genesis, and combined that were created outside of
    # kurtosis entirely, we'll use those and exit. This is like a
    # permissionless use case or a use case where we're starting from
    # recovered network
    if [[ -e "${input_dir}/genesis.json" && -e "${input_dir}/combined.json" ]]; then
        _echo_ts "We have a genesis and combined output file from a previous deployment"
        cp "$input_dir"/genesis.json "$output_dir"/
        cp "$input_dir"/combined.json "$output_dir"/
        cp "$input_dir"/dynamic-*.json "$output_dir"/
        jq '.firstBatchData' "$input_dir"/combined.json > "$output_dir"/first-batch-config.json
        popd || exit 1
        exit
    fi

    _echo_ts "Waiting for the L1 RPC to be available"
    _wait_for_rpc_to_be_available "{{.l1_rpc_url}}" "{{.l1_preallocated_mnemonic}}"
    _echo_ts "L1 RPC is now available"

    _echo_ts "Funding important accounts on L1"
    _fund_account_on_l1 "admin" "{{.l2_admin_address}}"
    _fund_account_on_l1 "sequencer" "{{.l2_sequencer_address}}"
    _fund_account_on_l1 "aggregator" "{{.l2_aggregator_address}}"
    _fund_account_on_l1 "sovereignadmin" "{{.l2_sovereignadmin_address}}"

    _echo_ts "Setting up local agglayer-contracts repo for deployment"
    pushd "$contracts_dir" || exit 1
    cp "$input_dir"/deploy_parameters.json "$contracts_dir"/deployment/v2/deploy_parameters.json
    cp "$input_dir"/create_rollup_parameters.json "$contracts_dir"/deployment/v2/create_rollup_parameters.json
    # Set up the hardhat environment.
    sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts
    # Set up a foundry project in case we do a gas token or dac deployment.
    printf "[profile.default]\nsrc = 'contracts'\nout = 'out'\nlibs = ['node_modules']\n" > foundry.toml

    is_first_rollup=0 # an indicator if this deployment is doing the first setup of the agglayer etc
    if [[ ! -e "$output_dir"/combined.json ]]; then
        _echo_ts "It looks like this is the first rollup so we'll deploy the LxLy and Rollup Manager"
        _deploy_agglayer_manager
        is_first_rollup=1
    else
        _echo_ts "Skipping deployment of the Rollup Manager and LxLy"
        cp "$output_dir"/deploy_output.json "$contracts_dir"/deployment/v2/
    fi

    # Combine contract deploy files.
    # At this point, all of the contracts /should/ have been deployed.
    # Now we can combine all of the files and put them into the general zkevm folder.
    _echo_ts "Combining contract deploy files"
    mkdir -p "$output_dir"
    cp "$contracts_dir"/deployment/v2/deploy_*.json "$output_dir"/

    popd || exit 1

    _echo_ts "Creating combined.json"
    pushd "$output_dir"/ || exit 1
    cp deploy_output.json combined.json
    cat combined.json

    # There are a bunch of fields that need to be renamed in order for the
    # older fork7 code to be compatible with some of the fork8
    # automations. This schema matching can be dropped once this is
    # versioned up to 8
    # DEPRECATED we will likely remove support for anything before fork 9 soon
    fork_id="{{.zkevm_fork_id}}"
    if [[ $fork_id -lt 8 && $fork_id -ne 0 ]]; then
        jq '.AgglayerManager = .polygonRollupManager' combined.json > c.json; mv c.json combined.json
        jq '.deploymentRollupManagerBlockNumber = .deploymentBlockNumber' combined.json > c.json; mv c.json combined.json
        jq '.upgradeToULxLyBlockNumber = .deploymentBlockNumber' combined.json > c.json; mv c.json combined.json
        jq '.polygonDataCommitteeAddress = .polygonDataCommittee' combined.json > c.json; mv c.json combined.json
    fi

    # Configure contracts.

    if [[ $is_first_rollup -eq 1 ]]; then
        # Grant the aggregator role to the agglayer so that it can also verify batches.
        # cast keccak "TRUSTED_AGGREGATOR_ROLE"
        _echo_ts "Granting the aggregator role to the agglayer so that it can also verify batches"
        role_bytes32=$(cast keccak "TRUSTED_AGGREGATOR_ROLE")
        cast send \
            --private-key "{{.l2_admin_private_key}}" \
            --rpc-url "{{.l1_rpc_url}}" \
            "$(jq -r '.AgglayerManager' combined.json)" \
            'grantRole(bytes32,address)' \
            "$role_bytes32" "{{.l2_aggregator_address}}"
    fi

    # The sequencer needs to pay POL when it sequences batches.
    # This gets refunded when the batches are verified on L1.
    # In order for this to work the rollup address must be approved to transfer the sequencers' POL tokens.
    _echo_ts "Minting POL token on L1 for the sequencer"
    cast send \
        --private-key "{{.l2_sequencer_private_key}}" \
        --legacy \
        --rpc-url "{{.l1_rpc_url}}" \
        "$(jq -r '.polTokenAddress' combined.json)" \
        'mint(address,uint256)' \
        "{{.l2_sequencer_address}}" 1000000000000000000000000000

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

# used always except for l1_custom_genesis=True and pessimistic consensus
create_agglayer_rollup() {
    _echo_ts "Executing function create_agglayer_rollup"

    # This script is responsible for deploying the contracts for zkEVM/CDK.
    global_log_level="{{.global_log_level}}"
    if [[ $global_log_level == "debug" ]]; then
        set -x
    fi

    _echo_ts "Waiting for the L1 RPC to be available"
    _wait_for_rpc_to_be_available "{{.l1_rpc_url}}" "{{.l1_preallocated_mnemonic}}"
    _echo_ts "L1 RPC is now available"

    cp "$input_dir"/deploy_parameters.json "$contracts_dir"/deployment/v2/deploy_parameters.json
    # shellcheck disable=SC1054,SC1072,SC1083
    {{ if eq .consensus_contract_type "ecdsa-multisig" }}
    cp "$input_dir"/create_new_rollup.json "$contracts_dir"/deployment/v2/create_rollup_parameters.json
    # shellcheck disable=SC1073,1009
    {{ else }}
    cp "$input_dir"/create_rollup_parameters.json "$contracts_dir"/deployment/v2/create_rollup_parameters.json
    {{ end }}

    _create_genesis

    _echo_ts "Setting up local agglayer-contracts repo for deployment"
    pushd "$contracts_dir" || exit 1
    # Set up the hardhat environment. It needs to be executed even in custom genesis mode
    sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' hardhat.config.ts

    # Deploy gas token
    # shellcheck disable=SC1054,SC1072,SC1083
    {{ if .gas_token_enabled }}
        {{ if or (eq .gas_token_address "0x0000000000000000000000000000000000000000") (eq .gas_token_address "") }}
        _echo_ts "Deploying gas token to L1"
        # Foundry cache is corrupted/invalid at this point for some reason
        # Maybe the source image has cached older contract versions
        rm -fr out cache
            {{ if eq .consensus_contract_type "ecdsa-multisig" }}
            forge create \
                --broadcast \
                --json \
                --rpc-url "{{.l1_rpc_url}}" \
                --mnemonic "{{.l1_preallocated_mnemonic}}" \
                contracts/mocks/ERC20PermitMock.sol:ERC20PermitMock \
                --constructor-args "CDK Gas Token" "CDK" "{{.l2_admin_address}}" "1000000000000000000000000" \
                > gasToken-erc20.json
            jq \
                --slurpfile c gasToken-erc20.json \
                '.gasTokenAddress = $c[0].deployedTo | .sovereignParams.sovereignWETHAddress = $c[0].deployedTo' \
                "$input_dir"/create_new_rollup.json \
                > "$contracts_dir"/deployment/v2/create_rollup_parameters.json
            {{ else }}
            forge create \
                --broadcast \
                --json \
                --rpc-url "{{.l1_rpc_url}}" \
                --mnemonic "{{.l1_preallocated_mnemonic}}" \
                contracts/mocks/ERC20PermitMock.sol:ERC20PermitMock \
                --constructor-args "CDK Gas Token" "CDK" "{{.l2_admin_address}}" "1000000000000000000000000" \
                > gasToken-erc20.json
            jq \
                --slurpfile c gasToken-erc20.json \
                '.gasTokenAddress = $c[0].deployedTo' \
                "$input_dir"/create_rollup_parameters.json \
                > "$contracts_dir"/deployment/v2/create_rollup_parameters.json
            {{ end }}
        {{ else }}
        _echo_ts "Using L1 pre-deployed gas token: {{ .gas_token_address }}"
            {{ if eq .consensus_contract_type "ecdsa-multisig" }}
            jq \
                --arg c "{{ .gas_token_address }}" \
                '.gasTokenAddress = $c' \
                "$input_dir"/create_new_rollup.json \
                > "$contracts_dir"/deployment/v2/create_rollup_parameters.json
            {{ else }}
            jq \
                --arg c "{{ .gas_token_address }}" \
                '.gasTokenAddress = $c' \
                "$input_dir"/create_rollup_parameters.json \
                > "$contracts_dir"/deployment/v2/create_rollup_parameters.json
            {{ end }}
        {{ end }}
    {{ end }}

    cp "$contracts_dir"/deployment/v2/genesis.json "$output_dir"/

    {{ if eq .consensus_contract_type "ecdsa-multisig" }}
    # Set gasTokenAddress and sovereignWETHAddress to zero address if they have "<no value>"
    jq 'walk(if type == "object" then 
            with_entries(
                if .key == "gasTokenAddress" and (.value == "<no value>" or .value == "") then 
                    .value = "0x0000000000000000000000000000000000000000" 
                elif .key == "sovereignWETHAddress" and (.value == "<no value>" or .value == "") then 
                    .value = "0x0000000000000000000000000000000000000000"
                else 
                    . 
                end
            ) 
        else 
            . 
        end)' \
        "$contracts_dir"/deployment/v2/create_rollup_parameters.json > temp.json && \
        mv temp.json "$contracts_dir"/deployment/v2/create_rollup_parameters.json
    {{ end }}

    # Comment out aggLayerGateway.addDefaultAggchainVKey for additional rollups with same AggchainVKeySelector and OwnedAggchainVKey
    if [[ "{{ .l2_network_id }}" != "1" ]]; then
    sed -i '/await aggLayerGateway\.addDefaultAggchainVKey(/,/);/s/^/\/\/ /' "$contracts_dir"/deployment/v2/4_createRollup.ts
    fi

    # Do not create another rollup in the case of an optimism rollup. This will be done in run-sovereign-setup.sh
    if [[ "{{.sequencer_type}}" != "op-geth" ]]; then
        _echo_ts "Step 5: Creating Rollup/Validium/ECDSAMultisig"
        npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee 05_create_rollup.out
        # Support for new output file format
        if [[ $(echo deployment/v2/create_rollup_output_* | wc -w) -gt 1 ]]; then
            _echo_ts "There are multiple create rollup output files. We don't know how to handle this situation"
            exit 1
        fi
        if [[ $(echo deployment/v2/create_rollup_output_* | wc -w) -eq 1 ]]; then
            mv deployment/v2/create_rollup_output_* deployment/v2/create_rollup_output.json
        fi
        if [[ ! -e deployment/v2/create_rollup_output.json ]]; then
            _echo_ts "The create_rollup_output.json file was not created after running createRollup"
            exit 1
        fi
    fi

    # Combine contract deploy files.
    # At this point, all of the contracts /should/ have been deployed.
    # Now we can combine all of the files and put them into the general zkevm folder.

    # Check create_rollup_output.json exists before copying it.
    # For the case of OP rollup, create_rollup_output.json will not be created.
    if [[ -e "$contracts_dir"/deployment/v2/create_rollup_output.json ]]; then
        cp "$contracts_dir"/deployment/v2/create_rollup_output.json "$output_dir"/
    else
        echo "File "$contracts_dir"/deployment/v2/create_rollup_output.json does not exist."
    fi
    cp "$contracts_dir"/deployment/v2/create_rollup_parameters.json "$output_dir"/
    popd || exit 1

    _echo_ts "Modifying combined.json"
    pushd "$output_dir"/ || exit 1

    cp genesis.json genesis.original.json
    # Check create_rollup_output.json exists before copying it.
    # For the case of OP rollup, create_rollup_output.json will not be created.
    if [[ -e create_rollup_output.json ]]; then
        echo "File create_rollup_output.json exists. Combining files..."
        jq --slurpfile rollup create_rollup_output.json '. + $rollup[0]' deploy_output.json > combined.json
    else
        echo "File create_rollup_output.json does not exist. Trying to copy deploy_output.json to combined.json."
        cp deploy_output.json combined.json
    fi
    jq '.polygonZkEVML2BridgeAddress = .AgglayerBridge' combined.json > c.json; mv c.json combined.json

    # Add the L2 GER Proxy address in combined.json
    l2_ger_address=$(jq -r '.genesis[] | select(.contractName == "PolygonZkEVMGlobalExitRootL2 proxy") | .address' "$output_dir"/genesis.json)
    if [[ -z "$l2_ger_address" ]]; then
        l2_ger_address=$(jq -r '.genesis[] | select(.contractName == "LegacyAgglayerGERL2 proxy") | .address' "$output_dir"/genesis.json)
    fi
    if [[ -z "$l2_ger_address" ]]; then
        _echo_ts "Error: No L2 GER Proxy address found in genesis.json"
        exit 1
    fi
    jq --arg a "$l2_ger_address" '.LegacyAgglayerGERL2 = $a' combined.json > c.json; mv c.json combined.json

    {{ if .gas_token_enabled }}
    jq --slurpfile cru "$contracts_dir"/deployment/v2/create_rollup_parameters.json '.gasTokenAddress = $cru[0].gasTokenAddress' combined.json > c.json; mv c.json combined.json

    gas_token_address=$(jq -r '.gasTokenAddress' "$output_dir"/combined.json)
    agglayer_bridge=$(jq -r '.AgglayerBridge' "$output_dir"/combined.json)
    # Bridge gas token to L2 to prevent bridge underflow reverts
    _echo_ts "Bridging initial gas token to L2 to prevent bridge underflow reverts..."
    polycli ulxly bridge asset \
        --bridge-address "$agglayer_bridge" \
        --destination-address "0x0000000000000000000000000000000000000000" \
        --destination-network "{{.l2_network_id}}" \
        --private-key "{{.l2_admin_private_key}}" \
        --rpc-url "{{.l1_rpc_url}}" \
        --value 10000000000000000000000 \
        --token-address $gas_token_address
    {{ end }}


    # There are a bunch of fields that need to be renamed in order for the
    # older fork7 code to be compatible with some of the fork8
    # automations. This schema matching can be dropped once this is
    # versioned up to 8
    # DEPRECATED we will likely remove support for anything before fork 9 soon
    fork_id="{{.zkevm_fork_id}}"
    if [[ $fork_id -lt 8 && $fork_id -ne 0 ]]; then
        jq '.createRollupBlockNumber = .createRollupBlock' combined.json > c.json; mv c.json combined.json
    fi

    # NOTE there is a disconnect in the necessary configurations here between the validium node and the zkevm node
    jq --slurpfile c combined.json '.rollupCreationBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
    jq --slurpfile c combined.json '.rollupManagerCreationBlockNumber = $c[0].upgradeToULxLyBlockNumber' genesis.json > g.json; mv g.json genesis.json
    jq --slurpfile c combined.json '.genesisBlockNumber = $c[0].createRollupBlockNumber' genesis.json > g.json; mv g.json genesis.json
    jq --slurpfile c combined.json '.L1Config = {chainId:{{.l1_chain_id}}}' genesis.json > g.json; mv g.json genesis.json
    jq --slurpfile c combined.json '.L1Config.polygonZkEVMGlobalExitRootAddress = $c[0].AgglayerGER' genesis.json > g.json; mv g.json genesis.json
    jq --slurpfile c combined.json '.L1Config.polygonRollupManagerAddress = $c[0].AgglayerManager' genesis.json > g.json; mv g.json genesis.json
    jq --slurpfile c combined.json '.L1Config.polTokenAddress = $c[0].polTokenAddress' genesis.json > g.json; mv g.json genesis.json
    jq --slurpfile c combined.json '.L1Config.polygonZkEVMAddress = $c[0].rollupAddress' genesis.json > g.json; mv g.json genesis.json
    jq --slurpfile c combined.json '.bridgeGenBlockNumber = $c[0].createRollupBlockNumber' combined.json > c.json; mv c.json combined.json

    _echo_ts "Final combined.json is ready:"
    cp combined.json "combined{{.deployment_suffix}}.json"
    cat combined.json

    {{ if eq .sequencer_type "cdk-erigon" }}
    _echo_ts "Approving the rollup address to transfer POL tokens on behalf of the sequencer"
    cast send \
        --private-key "{{.l2_sequencer_private_key}}" \
        --legacy \
        --rpc-url "{{.l1_rpc_url}}" \
        "$(jq -r '.polTokenAddress' combined.json)" \
        'approve(address,uint256)(bool)' \
        "$(jq -r '.rollupAddress' combined.json)" 1000000000000000000000000000
    {{ end }}

    {{ if eq .consensus_contract_type "cdk-validium" }}
    # The DAC needs to be configured with a required number of signatures.
    # Right now the number of DAC nodes is not configurable.
    # If we add more nodes, we'll need to make sure the urls and keys are sorted.
    _echo_ts "Setting the data availability committee"
    cast send \
        --private-key "{{.l2_admin_private_key}}" \
        --rpc-url "{{.l1_rpc_url}}" \
        "$(jq -r '.polygonDataCommitteeAddress' combined.json)" \
        'function setupCommittee(uint256 _requiredAmountOfSignatures, string[] urls, bytes addrsBytes) returns()' \
        1 ["http://cdk-data-availability{{.deployment_suffix}}:{{.cdk_data_availability_rpc_port_number}}"] "{{.l2_dac_address}}"

    # The DAC needs to be enabled with a call to set the DA protocol.
    _echo_ts "Setting the data availability protocol"
    cast send \
        --private-key "{{.l2_admin_private_key}}" \
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
    if ! output_json=$(jq "$jq_script" "$output_dir"/genesis.json); then
        _echo_ts "Error processing JSON with jq"
        exit 1
    fi

    # Write the output JSON to a file
    if ! echo "$output_json" | jq . > "dynamic-{{.chain_name}}-allocs.json"; then
        _echo_ts "Error writing to file dynamic-{{.chain_name}}-allocs.json"
        exit 1
    fi

    _echo_ts "Transformation complete. Output written to dynamic-{{.chain_name}}-allocs.json"
    if [[ -e create_rollup_output.json ]]; then
        jq '{"root": .root, "timestamp": 0, "gasLimit": 0, "difficulty": 0}' "$output_dir"/genesis.json > "dynamic-{{.chain_name}}-conf.json"
        batch_timestamp=$(jq '.firstBatchData.timestamp' combined.json)
        jq --arg bt "$batch_timestamp" '.timestamp |= ($bt | tonumber)' "dynamic-{{.chain_name}}-conf.json" > tmp_output.json
        mv tmp_output.json "dynamic-{{.chain_name}}-conf.json"
    else
        echo "Without create_rollup_output.json, there is no batch_timestamp available"
        jq '{"root": .root, "timestamp": 0, "gasLimit": 0, "difficulty": 0}' "$output_dir"/genesis.json > "dynamic-{{.chain_name}}-conf.json"
    fi

    # zkevm.initial-batch.config
    jq '.firstBatchData' combined.json > "$output_dir"/first-batch-config.json

    if [[ ! -s "dynamic-{{.chain_name}}-conf.json" ]]; then
        _echo_ts "Error creating the dynamic kurtosis config"
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
    touch "${output_dir}/.init-complete{{.deployment_suffix}}.lock"

}

# Called always as last step after l1 agglayer contracts are deployed
update_ger() {
    _echo_ts "Executing function update_ger"

    set -e
    # TODO we should understand if this is still need and if so we
    # shouldn't run it if the network has already been deployed

    # Setup some vars for use later on
    # The private key used to send transactions
    private_key="{{.l2_admin_private_key}}"

    # The bridge address
    agglayer_bridge="$(jq --raw-output '.AgglayerBridge' ${output_dir}/combined.json)"

    # Grab the endpoints for l1
    l1_rpc_url="{{.l1_rpc_url}}"

    # The signature for bridging is long - just putting it into a var
    bridge_sig="bridgeAsset(uint32 destinationNetwork, address destinationAddress, uint256 amount, address token, bool forceUpdateGlobalExitRoot, bytes permitData)"

    # Get our variables organized
    destination_net="7" # random value (better to not use 1 as it could interfere with the network being deployed)
    destination_addr="0x0000000000000000000000000000000000000000"
    amount=0
    token="0x0000000000000000000000000000000000000000"
    update_ger=true
    permit_data="0x"

    # Generate the call data, this is useful just to examine what the call will look like
    echo "Generating the call data for the bridge tx..."
    cast calldata "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"

    # Perform an eth_call to make sure the tx will work
    echo "Performing an eth call to make sure the bridge tx will work..."
    cast call --rpc-url "$l1_rpc_url" "$agglayer_bridge" "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"

    # Publish the actual transaction!
    echo "Publishing the bridge tx..."
    cast send --rpc-url "$l1_rpc_url" --private-key "$private_key" "$agglayer_bridge" "$bridge_sig" "$destination_net" "$destination_addr" "$amount" "$token" "$update_ger" "$permit_data"

}

# Called always if we are deploying an Optimism Rollup
initialize_rollup() {
    _echo_ts "Executing function initialize_rollup"

    # Initialize rollup
    pushd "$contracts_dir" || exit 1

    ts=$(date +%s)
    # The startingBlockNumber and sp1_starting_timestamp values in create_new_rollup.json file needs to be populated with the below commands.
    deployOPSuccinct="{{ eq .consensus_contract_type "fep" }}"
    if [[ $deployOPSuccinct == true ]]; then
        echo "Configuring OP Succinct setup..."
        jq --slurpfile l2 "$output_dir"/opsuccinctl2ooconfig.json '
        .deployerPvtKey = .aggchainManagerPvtKey |
        .aggchainParams.initParams.l2BlockTime = $l2[0].l2BlockTime |
        .aggchainParams.initParams.rollupConfigHash = $l2[0].rollupConfigHash |
        .aggchainParams.initParams.startingOutputRoot = $l2[0].startingOutputRoot |
        .aggchainParams.initParams.startingTimestamp = $l2[0].startingTimestamp |
        .aggchainParams.initParams.startingBlockNumber = $l2[0].startingBlockNumber |
        .aggchainParams.initParams.submissionInterval = $l2[0].submissionInterval |
        .aggchainParams.initParams.aggregationVkey = $l2[0].aggregationVkey |
        .aggchainParams.initParams.rangeVkeyCommitment = $l2[0].rangeVkeyCommitment
        ' "$input_dir"/create_new_rollup.json > "$output_dir"/initialize_rollup.json

        jq --slurpfile l2 "$output_dir"/opsuccinctl2ooconfig.json \ '.verifierAddress = $l2[0].verifier' "$output_dir"/initialize_rollup.json > "$output_dir"/initialize_rollup${ts}.json
        cp "$output_dir"/initialize_rollup${ts}.json "$output_dir"/initialize_rollup.json

        # Extract the rollup manager address from the JSON file. .zkevm_agglayer_manageress is not available at the time of importing this script.
        # So a manual extraction of AgglayerManager is done here.
        # Even with multiple op stack deployments, the rollup manager address can be retrieved from combined{{.deployment_suffix}}.json because it must be constant.
        agglayer_manager=$(jq -r '.rollupManagerAddress' "$output_dir"/create_rollup_output.json)
        rollup_id=$(jq -r '.rollupID' "$output_dir"/create_rollup_output.json)

        # It looks like setting up of the rollupid isn't necessary because the rollupid is determined based on the chainid
        jq --arg rum "$agglayer_manager" --arg rid "$rollup_id" --arg chainid "{{.l2_chain_id}}" '.rollupManagerAddress = $rum | .rollupID = $rid | .chainID = ($chainid | tonumber)' "$output_dir"/initialize_rollup.json > "$output_dir"/initialize_rollup.json.tmp
        mv "$output_dir"/initialize_rollup.json.tmp "$output_dir"/initialize_rollup.json

        cp "$output_dir"/initialize_rollup.json "$contracts_dir"/tools/initializeRollup/initialize_rollup.json

        npx hardhat run tools/initializeRollup/initializeRollup.ts --network localhost 2>&1 | tee 08_init_rollup.out
    fi

    # Save Rollup Information to a file.
    agglayer_manager=$(jq -r '.AgglayerManager' "$output_dir"/combined.json)
    cast call --json --rpc-url "{{.l1_rpc_url}}" "$agglayer_manager" 'rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' "{{.l2_network_id}}" | jq '{"sovereignRollupContract": .[0], "rollupChainID": .[1], "verifier": .[2], "forkID": .[3], "lastLocalExitRoot": .[4], "lastBatchSequenced": .[5], "lastVerifiedBatch": .[6], "_legacyLastPendingState": .[7], "_legacyLastPendingStateConsolidated": .[8], "lastVerifiedBatchBeforeUpgrade": .[9], "rollupTypeID": .[10], "rollupVerifierType": .[11]}' > "$contracts_dir"/sovereign-rollup-out.json

    rpc_url="{{.op_el_rpc_url}}"
    # This is the default prefunded account for the OP Network
    private_key=$(cast wallet private-key --mnemonic 'test test test test test test test test test test test junk')

    cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" "{{.l2_sovereignadmin_address}}"
    cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" "{{.l2_aggoracle_address}}"
    cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" "{{.l2_claimsponsor_address}}"

    bridge_impl_addr=$(jq -r '.genesisSCNames["AgglayerBridgeL2 implementation"]' "$output_dir"/create-sovereign-genesis-output.json)
    bridge_proxy_addr=$(jq -r '.genesisSCNames["AgglayerBridgeL2 proxy"]' "$output_dir"/create-sovereign-genesis-output.json)
    ger_impl_addr=$(jq -r '.genesisSCNames["AgglayerGERL2 implementation"]' "$output_dir"/create-sovereign-genesis-output.json)
    ger_proxy_addr=$(jq -r '.genesisSCNames["AgglayerGERL2 proxy"]' "$output_dir"/create-sovereign-genesis-output.json)

    _echo_ts "bridge_impl_addr: $bridge_impl_addr, bridge_proxy_addr: $bridge_proxy_addr, ger_impl_addr: $ger_impl_addr, ger_proxy_addr: $ger_proxy_addr"

    # Save the contract addresses to the sovereign-rollup-out.json file
    jq --arg bridge_impl_addr "$bridge_impl_addr" '. += {"bridge_impl_addr": $bridge_impl_addr}' "$contracts_dir"/sovereign-rollup-out.json > "$contracts_dir"/sovereign-rollup-out.json.temp && mv "$contracts_dir"/sovereign-rollup-out.json.temp "$contracts_dir"/sovereign-rollup-out.json
    jq --arg ger_impl_addr "$ger_impl_addr" '. += {"ger_impl_addr": $ger_impl_addr}' "$contracts_dir"/sovereign-rollup-out.json > "$contracts_dir"/sovereign-rollup-out.json.temp && mv "$contracts_dir"/sovereign-rollup-out.json.temp "$contracts_dir"/sovereign-rollup-out.json
    jq --arg ger_proxy_addr "$ger_proxy_addr" '. += {"ger_proxy_addr": $ger_proxy_addr}' "$contracts_dir"/sovereign-rollup-out.json > "$contracts_dir"/sovereign-rollup-out.json.temp && mv "$contracts_dir"/sovereign-rollup-out.json.temp "$contracts_dir"/sovereign-rollup-out.json
    jq --arg bridge_proxy_addr "$bridge_proxy_addr" '. += {"bridge_proxy_addr": $bridge_proxy_addr}' "$contracts_dir"/sovereign-rollup-out.json > "$contracts_dir"/sovereign-rollup-out.json.temp && mv "$contracts_dir"/sovereign-rollup-out.json.temp "$contracts_dir"/sovereign-rollup-out.json

    # Extract values from sovereign-rollup-out.json
    sovereignRollupContract=$(jq -r '.sovereignRollupContract' "$contracts_dir"/sovereign-rollup-out.json)
    rollupChainID=$(jq -r '.rollupChainID' "$contracts_dir"/sovereign-rollup-out.json)
    verifier=$(jq -r '.verifier' "$contracts_dir"/sovereign-rollup-out.json)
    forkID=$(jq -r '.forkID' "$contracts_dir"/sovereign-rollup-out.json)
    lastLocalExitRoot=$(jq -r '.lastLocalExitRoot' "$contracts_dir"/sovereign-rollup-out.json)
    lastBatchSequenced=$(jq -r '.lastBatchSequenced' "$contracts_dir"/sovereign-rollup-out.json)
    lastVerifiedBatch=$(jq -r '.lastVerifiedBatch' "$contracts_dir"/sovereign-rollup-out.json)
    _legacyLastPendingState=$(jq -r '._legacyLastPendingState' "$contracts_dir"/sovereign-rollup-out.json)
    _legacyLastPendingStateConsolidated=$(jq -r '._legacyLastPendingStateConsolidated' "$contracts_dir"/sovereign-rollup-out.json)
    lastVerifiedBatchBeforeUpgrade=$(jq -r '.lastVerifiedBatchBeforeUpgrade' "$contracts_dir"/sovereign-rollup-out.json)
    rollupTypeID=$(jq -r '.rollupTypeID' "$contracts_dir"/sovereign-rollup-out.json)
    rollupVerifierType=$(jq -r '.rollupVerifierType' "$contracts_dir"/sovereign-rollup-out.json)

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
        '.LegacyAgglayerGERL2 = $ger_proxy_addr |
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
        "${output_dir}/combined.json" > "${output_dir}/combined.json.temp"

    mv "${output_dir}/combined.json.temp" "${output_dir}/combined.json"

    # Copy the updated combined.json to a new file with the deployment suffix
    cp "${output_dir}/combined.json" "${output_dir}/combined{{.deployment_suffix}}.json"

    # Contract addresses to extract from combined.json and check for bytecode
    # shellcheck disable=SC2034
    l1_contract_names=(
        "AgglayerManager"
        "AgglayerBridge"
        "AgglayerGER"
        "AgglayerGateway"
        "pessimisticVKeyRouteALGateway.verifier"
        "polTokenAddress"
        "zkEVMDeployerContract"
        "timelockContractAddress"
        "rollupAddress"
    )

    # shellcheck disable=SC2034
    l2_contract_names=(
        "polygonZkEVML2BridgeAddress"
        "LegacyAgglayerGERL2"
    )

    # JSON file to extract addresses from
    json_file="${output_dir}/combined.json"

    # Extract addresses
    # shellcheck disable=SC2128
    l1_contract_addresses=$(_extract_addresses l1_contract_names "$json_file")
    # shellcheck disable=SC2128
    l2_contract_addresses=$(_extract_addresses l2_contract_names "$json_file")

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
    rollupID=$(cast call "$agglayer_manager" "chainIDToRollupID(uint64)(uint32)" "{{.l2_chain_id}}" --rpc-url "{{.l1_rpc_url}}")
    # shellcheck disable=SC2050
    if [[ $rollupID == "1" ]] && [[ "{{ .consensus_contract_type }}" != "ecdsa-multisig" ]]; then
        # FIXME - Temporary work around to make sure the default aggkey is configured
        cast send --rpc-url "{{.l1_rpc_url}}" --private-key "{{.l2_admin_private_key}}" "$(jq -r '.AgglayerGateway' ${output_dir}/combined.json)" "addDefaultAggchainVKey(bytes4,bytes32)" "{{.aggchain_vkey_selector}}" "{{.aggchain_vkey_hash}}" 
        true
    fi
}

# Called from main when optimism rollup
fund_addresses() {
    _echo_ts "Executing function fund_addresses"

    # Exit on error
    set -e

    # Validate required environment variables
    if [[ -z "$RPC_URL" ]]; then
        echo "Error: RPC_URL environment variable is not set."
        exit 1
    fi

    if [[ -z "$ADDRESSES_TO_FUND" ]]; then
        echo "Error: ADDRESSES_TO_FUND environment variable is not set."
        exit 1
    fi

    if [[ -z "$L2_FUNDING_AMOUNT" ]]; then
        echo "Error: L2_FUNDING_AMOUNT environment variable is not set."
        exit 1
    fi

    # The op l2 's rpc url
    EXPECT_URL="http://op-el-1-op-geth-op-node$DEPLOYMENT_SUFFIX:8545"

    # Set private key based on RPC_URL
    if [[ "$RPC_URL" == "$EXPECT_URL" ]]; then
        # Default optimism-package preallocated mnemonic
        if ! private_key=$(cast wallet private-key --mnemonic "test test test test test test test test test test test junk" 2>/dev/null) || [[ -z "$private_key" ]]; then
            echo "Error: Failed to derive private key from mnemonic."
            exit 1
        fi
    else
        if [[ -z "$L1_PREALLOCATED_MNEMONIC" ]]; then
            echo "Error: L1_PREALLOCATED_MNEMONIC environment variable is not set for non-default RPC."
            exit 1
        fi
        if ! private_key=$(cast wallet private-key --mnemonic "$L1_PREALLOCATED_MNEMONIC" 2>/dev/null) || [[ -z "$private_key" ]]; then
            echo "Error: Failed to derive private key from mnemonic."
            exit 1
        fi
    fi

    # Fund addresses
    IFS=';' read -ra addresses <<<"$ADDRESSES_TO_FUND"

    # Validate addresses and fund them
    for address in "${addresses[@]}"; do
        # Basic address validation (ensure it’s a valid Ethereum address)
        if ! [[ "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo "Error: Invalid Ethereum address: $address"
            continue
        fi

        echo "Funding $address with $L2_FUNDING_AMOUNT"
        if ! cast send \
            --private-key "$private_key" \
            --rpc-url "$RPC_URL" \
            --value "$L2_FUNDING_AMOUNT" \
            "$address" >/dev/null 2>&1; then
            echo "Error: Failed to fund $address"
        else
            echo "Successfully funded $address"
        fi
    done
}

# Called for erigon stacks
l2_legacy_fund_accounts() {
    _echo_ts "Executing function l2_legacy_fund_accounts"

    global_log_level="{{.global_log_level}}"
    if [[ $global_log_level == "debug" ]]; then
        set -x
    fi

    _wait_for_rpc_to_be_available() {
        local counter=0
        local max_retries=20
        local retry_interval=5

        until cast send --legacy \
                        --rpc-url "$l2_rpc_url" \
                        --private-key "{{.l2_admin_private_key}}" \
                        --value 0 "{{.l2_sequencer_address}}" &> /dev/null; do
            ((counter++))
            _echo_ts "Can't send L2 transfers yet... Retrying ($counter)..."
            if [[ $counter -ge $max_retries ]]; then
                _echo_ts "Exceeded maximum retry attempts. Exiting."
                exit 1
            fi
            sleep $retry_interval
        done
    }

    _fund_account_on_l2() {
        local address="$1"
        _echo_ts "Funding $address"
        cast send \
            --legacy \
            --async \
            --nonce "$account_nonce" \
            --rpc-url "$l2_rpc_url" \
            --private-key "{{.l2_admin_private_key}}" \
            --value "{{.l2_funding_amount}}" \
            "$address"
        account_nonce="$((account_nonce + 1))"
    }

    if [[ -e "${output_dir}/.init-l2-complete{{.deployment_suffix}}.lock" ]]; then
        _echo_ts "This script has already been executed"
        exit 1
    fi

    if [[ -z "$l2_rpc_url" ]]; then
        echo "Error: l2_rpc_url is not set. Exiting."
        exit 1
    fi

    _echo_ts "Waiting for the L2 RPC to be available"
    _wait_for_rpc_to_be_available
    _echo_ts "L2 RPC is now available"

    eth_address="$(cast wallet address --private-key "{{.l2_admin_private_key}}")"
    account_nonce="$(cast nonce --rpc-url "$l2_rpc_url" "$eth_address")"

    _echo_ts "Funding claim sponsor account on l2"
    _fund_account_on_l2 "{{.l2_claimsponsor_address}}"   
}

# Called for erigon stacks
l2_contract_setup() {
    _echo_ts "Executing function l2_contract_setup"

    global_log_level="{{.global_log_level}}"
    if [[ $global_log_level == "debug" ]]; then
        set -x
    fi
    if [[ -e "${output_dir}/.init-l2-complete{{.deployment_suffix}}.lock" ]]; then
        _echo_ts "This script has already been executed"
        exit 1
    fi
    if [[ -z "$l2_rpc_url" ]]; then
        echo "Error: l2_rpc_url is not set. Exiting."
        exit 1
    fi

    _fund_account_on_l2() {
        local address="$1"
        _echo_ts "Funding $address"
        cast send \
            --legacy \
            --async \
            --nonce "$account_nonce" \
            --rpc-url "$l2_rpc_url" \
            --private-key "{{.l2_admin_private_key}}" \
            --value "{{.l2_funding_amount}}" \
            "$address"
        account_nonce="$((account_nonce + 1))"
    }

    eth_address="$(cast wallet address --private-key "{{.l2_admin_private_key}}")"
    account_nonce="$(cast nonce --rpc-url "$l2_rpc_url" "$eth_address")"

    _echo_ts "Funding accounts on l2"
    for (( i = 0; i < "{{.l2_accounts_to_fund}}"; i++ )); do
        address=$(cast wallet address --mnemonic "{{.l1_preallocated_mnemonic}}" --mnemonic-index "$i")
       _fund_account_on_l2 "$address"
    done

    # This deploys the deterministic deployment proxy found here:
    # https://github.com/Arachnid/deterministic-deployment-proxy. You can find the
    # signer_address, transaction, and deploy_address by building the repo or just
    # looking at the values in the README.
    signer_address="0x3fab184622dc19b6109349b94811493bf2a45362"
    gas_cost="0.01ether"
    transaction="0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222"
    deployer_address="0x4e59b44847b379578588920ca78fbf26c0b4956c"

    # We set this conditionally because older versions of cast use
    # `derive-private-key` while newer version use `private-key`.
    l1_private_key=$(cast wallet derive-private-key "{{.l1_preallocated_mnemonic}}" | grep "Private key:" | awk '{print $3}')
    if [[ -z "$l1_private_key" ]]; then
        l1_private_key=$(cast wallet private-key "{{.l1_preallocated_mnemonic}}")
    fi

    # shellcheck disable=SC2078
    if [[ "{{.l2_deploy_deterministic_deployment_proxy}}" ]]; then
        _echo_ts "Deploying deterministic deployment proxy on l2"
        cast send \
            --legacy \
            --rpc-url "$l2_rpc_url" \
            --private-key "{{.l2_admin_private_key}}" \
            --value "$gas_cost" \
            --nonce "$account_nonce" \
            "$signer_address"
        cast publish --rpc-url "$l2_rpc_url" "$transaction"
        if [[ $(cast code --rpc-url "$l2_rpc_url" $deployer_address) == "0x" ]]; then
            _echo_ts "No code at expected l2 address: $deployer_address"
            exit 1;
        fi
    else
        _echo_ts "Skipping deployment of deterministic deployment proxy on l2"
    fi

    # shellcheck disable=SC2078
    if [[ "{{.l1_deploy_lxly_bridge_and_call}}" || "{{.l2_deploy_lxly_bridge_and_call}}" ]]; then
        export ADDRESS_PROXY_ADMIN=0x242daE44F5d8fb54B198D03a94dA45B5a4413e21
        export ADDRESS_LXLY_BRIDGE=0x2a3DD3EB832aF982ec71669E178424b10Dca2EDe

        git clone --recursive https://github.com/AggLayer/lxly-bridge-and-call /opt/lxly-bridge-and-call
        cd /opt/lxly-bridge-and-call || exit 1
    fi

    # shellcheck disable=SC2078
    if [[ "{{.l1_deploy_lxly_bridge_and_call}}" ]]; then
        _echo_ts "Deploying lxly bridge and call on l1"
        export DEPLOYER_PRIVATE_KEY="$l1_private_key"
        forge script script/DeployInitBridgeAndCall.s.sol --rpc-url "{{.l1_rpc_url}}" --legacy --broadcast
    else
        _echo_ts "Skipping deployment of lxly bridge and call on l1"
    fi

    # shellcheck disable=SC2078
    if [[ "{{.l2_deploy_lxly_bridge_and_call}}" ]]; then
        _echo_ts "Deploying lxly bridge and call on l2"
        export DEPLOYER_PRIVATE_KEY="{{.l2_admin_private_key}}"
        forge script script/DeployInitBridgeAndCall.s.sol --rpc-url "$l2_rpc_url" --legacy --broadcast
    else
        _echo_ts "Skipping deployment of lxly bridge and call on l2"
    fi

    # The contract setup is done!
    touch "${output_dir}/.init-l2-complete{{.deployment_suffix}}.lock"

}

# This is called from main when optimism rollup to create the allocs that will be used by optimism-package
create_predeployed_op_genesis() {
    _echo_ts "Executing function create_predeployed_op_genesis"

    set -e

    pushd "$contracts_dir" || exit 1

    # FIXME Just in case for now... ideally we don't need this but the base image is hacky right now
    # git config --global --add safe.directory "$contracts_dir"

    # Extract the rollup manager address from the JSON file. .zkevm_agglayer_manageress is not available at the time of importing this script.
    # So a manual extraction of AgglayerManager is done here.
    # Even with multiple op stack deployments, the rollup manager address can be retrieved from combined{{.deployment_suffix}}.json because it must be constant.
    agglayer_manager="$(jq -r '.AgglayerManager' "${output_dir}/combined{{.deployment_suffix}}.json")"
    chainID="$(jq -r '.chainID' "${output_dir}/create_rollup_parameters.json")"
    rollup_id="$(cast call "$agglayer_manager" "chainIDToRollupID(uint64)(uint32)" "$chainID" --rpc-url "{{.l1_rpc_url}}")"
    gas_token_addr="$(jq -r '.gasTokenAddress' "${output_dir}/combined{{.deployment_suffix}}.json")"

    # Replace rollupManagerAddress with the extracted address
    # sed -i "s|\"rollupManagerAddress\": \".*\"|\"rollupManagerAddress\":\"$agglayer_manager\"|" /opt/contract-deploy/create-genesis-sovereign-params.json
    # jq --arg ruid "$rollup_id" '.rollupID = ($ruid | tonumber)'  /opt/contract-deploy/create-genesis-sovereign-params.json > /opt/contract-deploy/create-genesis-sovereign-params.json.tmp

    # Extract AggOracle Committee member addresses as a JSON array
    agg_oracle_committee_members=$(seq 0 $(( "{{ .agg_oracle_committee_total_members }}" - 1 )) | while read -r index; do
        cast wallet address --mnemonic "lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop" --mnemonic-index "$index"
    done | jq -R . | jq -s .)

    # By default, the AggOracle sender will be "{{ .l2_aggoracle_address }}", which is also the signer to update L2 GER.
    # But any of the addresses from the aggOracleCommittee should be able to sign the transaction. This will require change to AggOracle.EVMSender.EthTxManager.PrivateKeys
    # Append to aggOracleCommittee in the JSON file
    jq --argjson addrs "$agg_oracle_committee_members" '
    .aggOracleCommittee += $addrs
    ' "$input_dir"/create-genesis-sovereign-params.json > "$input_dir"/create-genesis-sovereign-params.json.tmp \
    && mv "$input_dir"/create-genesis-sovereign-params.json.tmp "$input_dir"/create-genesis-sovereign-params.json

    # shellcheck disable=SC1054,SC1083,SC1056,SC1072
    {{ if not .gas_token_enabled }}
    gas_token_addr=0x0000000000000000000000000000000000000000
    # shellcheck disable=SC1009,SC1054,SC1073
    {{ end }}

    jq --arg ROLLUPMAN "$agglayer_manager" \
    --arg ROLLUPID $rollup_id \
    --arg GAS_TOKEN_ADDR "$gas_token_addr" \
    '
    .rollupManagerAddress = $ROLLUPMAN |
    .rollupID = ($ROLLUPID | tonumber) |
    .gasTokenAddress = $GAS_TOKEN_ADDR
    ' "$input_dir"/create-genesis-sovereign-params.json > "$input_dir"/create-genesis-sovereign-params.json.tmp
    mv "$input_dir"/create-genesis-sovereign-params.json.tmp "$input_dir"/create-genesis-sovereign-params.json

    # Required files to run the script
    cp "$input_dir"/create-genesis-sovereign-params.json "$contracts_dir"/tools/createSovereignGenesis/create-genesis-sovereign-params.json
    # 2025-04-03 it's not clear which of these should be used at this point
    # cp /opt/contract-deploy/sovereign-genesis.json "$contracts_dir"/tools/createSovereignGenesis/genesis-base.json
    cp "$contracts_dir"/deployment/v2/genesis.json "$contracts_dir"/tools/createSovereignGenesis/genesis-base.json

    # Remove all existing output files if they exist
    find "$contracts_dir"/tools/createSovereignGenesis/ -maxdepth 1 -type f -name 'genesis-rollupID*' -exec rm {} +
    find "$contracts_dir"/tools/createSovereignGenesis/ -maxdepth 1 -type f -name 'output-rollupID*' -exec rm {} +

    # Run the script
    npx hardhat run ./tools/createSovereignGenesis/create-sovereign-genesis.ts --network localhost

    # Save the genesis file
    genesis_file=$(find "$contracts_dir"/tools/createSovereignGenesis/ -maxdepth 1 -type f -name 'genesis-rollupID*' 2>/dev/null | head -n 1)
    if [[ -f "$genesis_file" ]]; then
        cp "$genesis_file" "${output_dir}/sovereign-predeployed-genesis.json"
        echo "Predeployed Genesis file saved: ${output_dir}/sovereign-predeployed-genesis.json"
    else
        echo "No matching Genesis file found!"
        exit 1
    fi

    # Save tool output file
    output_file=$(find "$contracts_dir"/tools/createSovereignGenesis/ -maxdepth 1 -type f -name 'output-rollupID*' 2>/dev/null | head -n 1)
    if [[ -f "$output_file" ]]; then
        cp "$output_file" "${output_dir}/create-sovereign-genesis-output.json"
        echo "Output saved: ${output_dir}/create-sovereign-genesis-output.json"
    else
        echo "No matching Output file found!"
        exit 1
    fi

    # Copy aggoracle implementation and proxy address to combined.json
    if [[ "{{.use_agg_oracle_committee}}" ]]; then
    jq --arg impl "$(jq -r '.genesisSCNames["AggOracleCommittee implementation"]' ${output_dir}/create-sovereign-genesis-output.json)" \
    --arg proxy "$(jq -r '.genesisSCNames["AggOracleCommittee proxy"]' ${output_dir}/create-sovereign-genesis-output.json)" \
    '. + { "aggOracleCommitteeImplementationAddress": $impl, "aggOracleCommitteeProxyAddress": $proxy }' \
    ${output_dir}/combined.json > ${output_dir}/combined.json.tmp && mv ${output_dir}/combined.json.tmp ${output_dir}/combined.json
    fi

    python3 "$scripts_dir"/create_op_allocs.py
}

# Called from main when optimism rollup to create the rollup, using predeployed contracts on L2
create_sovereign_rollup_predeployed() {
    _echo_ts "Executing function create_sovereign_rollup_predeployed"

    # Create New Rollup Step
    pushd "$contracts_dir" || exit 1

    # Requirement to correctly configure contracts deployer
    export DEPLOYER_PRIVATE_KEY="{{.l2_admin_private_key}}"

    ts=$(date +%s)

    # Extract the rollup manager address from the JSON file. .zkevm_agglayer_manageress is not available at the time of importing this script.
    # So a manual extraction of AgglayerManager is done here.
    # Even with multiple op stack deployments, the rollup manager address can be retrieved from combined{{.deployment_suffix}}.json because it must be constant.
    agglayer_manager="$(jq -r '.AgglayerManager' "${output_dir}/combined{{.deployment_suffix}}.json")"

    # Replace rollupManagerAddress with the extracted address
    jq --arg rum "$agglayer_manager" '.rollupManagerAddress = $rum' "$input_dir"/create_new_rollup.json > "${input_dir}/create_new_rollup${ts}.json"
    cp "${input_dir}/create_new_rollup${ts}.json" "$input_dir"/create_new_rollup.json

    # Replace AgglayerManager with the extracted address
    jq --arg rum "$agglayer_manager" '.polygonRollupManagerAddress = $rum' "${input_dir}/add_rollup_type.json" > "${input_dir}/add_rollup_type${ts}.json"
    cp "${input_dir}/add_rollup_type${ts}.json" "${input_dir}/add_rollup_type.json"

    # This will require genesis.json and create_new_rollup.json to be correctly filled. We are using a pre-defined template for these.
    # The script and example files exist under https://github.com/0xPolygonHermez/zkevm-contracts/tree/v9.0.0-rc.5-pp/tools/createNewRollup
    # The templates being used here: create_new_rollup.json and genesis.json were directly referenced from the above source.

    cp "${input_dir}/add_rollup_type.json"   "$contracts_dir"/tools/addRollupType/add_rollup_type.json
    cp "$input_dir"/create_new_rollup.json "$contracts_dir"/tools/createNewRollup/create_new_rollup.json

    # 2025-04-03 - These are removed for now because the genesis is created later. I'm using the genesis that's created by 1_createGenesis - hopefully that's right.
    # cp /opt/contract-deploy/sovereign-genesis.json "$contracts_dir"/tools/addRollupType/genesis.json
    # cp /opt/contract-deploy/sovereign-genesis.json "$contracts_dir"/tools/createNewRollup/genesis.json
    cp "$contracts_dir"/deployment/v2/genesis.json  "$contracts_dir"/tools/addRollupType/genesis.json
    cp "$contracts_dir"/deployment/v2/genesis.json  "$contracts_dir"/tools/createNewRollup/genesis.json

    cp "${output_dir}/combined.json" "$contracts_dir"/deployment/v2/deploy_output.json

    deployOPSuccinct="{{ eq .consensus_contract_type "fep" }}"
    if [[ $deployOPSuccinct == true ]]; then
        rm "$contracts_dir"/tools/addRollupType/add_rollup_type_output-*.json
        npx hardhat run tools/addRollupType/addRollupType.ts --network localhost 2>&1 | tee 06_create_rollup_type.out
        cp "$contracts_dir"/tools/addRollupType/add_rollup_type_output-*.json "${output_dir}/add_rollup_type_output.json"
        rollup_type_id=$(jq -r '.rollupTypeID' "${output_dir}/add_rollup_type_output.json")
        jq --arg rtid "$rollup_type_id"  '.rollupTypeId = $rtid' "$contracts_dir"/tools/createNewRollup/create_new_rollup.json > "$contracts_dir"/tools/createNewRollup/create_new_rollup.json.tmp
        mv "$contracts_dir"/tools/createNewRollup/create_new_rollup.json.tmp "$contracts_dir"/tools/createNewRollup/create_new_rollup.json

        rm "$contracts_dir"/tools/createNewRollup/create_new_rollup_output_*.json
        npx hardhat run ./tools/createNewRollup/createNewRollup.ts --network localhost 2>&1 | tee 07_create_sovereign_rollup.out
        cp "$contracts_dir"/tools/createNewRollup/create_new_rollup_output_*.json "${output_dir}/create_rollup_output.json"
    else
        # shellcheck disable=SC2050
        if [[ "{{ .l2_network_id }}" != "1" ]]; then
            sed -i '/await aggLayerGateway\.addDefaultAggchainVKey(/,/);/s/^/\/\/ /' "$contracts_dir"/deployment/v2/4_createRollup.ts
        fi
        # In the case for PP deployments without OP-Succinct, use the 4_createRollup.ts script instead of the createNewRollup.ts tool.
        cp "$input_dir"/create_new_rollup.json "$contracts_dir"/deployment/v2/create_rollup_parameters.json
        npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee 05_create_sovereign_rollup.out
    fi

    # Save Rollup Information to a file.
    cast call --json --rpc-url "{{.l1_rpc_url}}" "$agglayer_manager" 'rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' "{{.l2_network_id}}" | jq '{"sovereignRollupContract": .[0], "rollupChainID": .[1], "verifier": .[2], "forkID": .[3], "lastLocalExitRoot": .[4], "lastBatchSequenced": .[5], "lastVerifiedBatch": .[6], "_legacyLastPendingState": .[7], "_legacyLastPendingStateConsolidated": .[8], "lastVerifiedBatchBeforeUpgrade": .[9], "rollupTypeID": .[10], "rollupVerifierType": .[11]}' > "$contracts_dir"/sovereign-rollup-out.json

}

# Caleld for optimism rollup when predeployed_contracts is set to false, which I do believe never happens
create_sovereign_rollup() {
    _echo_ts "Executing function create_sovereign_rollup"

    # Requirement to correctly configure contracts deployer
    export DEPLOYER_PRIVATE_KEY="{{.l2_admin_private_key}}"

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
    cd "$contracts_dir" || exit

    # The startingBlockNumber and sp1_starting_timestamp values in create_new_rollup.json file needs to be populated with the below commands.
    # It follows the same logic which exist in deploy-op-succinct-contracts.sh to populate these values.
    starting_block_number=$(cast block-number --rpc-url "{{.l1_rpc_url}}")
    starting_timestamp=$(cast block --rpc-url "{{.l1_rpc_url}}" -f timestamp "$starting_block_number")
    # Directly insert the values into the create_new_rollup.json file.
    sed -i \
    -e "s/\"startingBlockNumber\": [^,}]*/\"startingBlockNumber\": $starting_block_number/" \
    -e "s/\"startingTimestamp\": [^,}]*/\"startingTimestamp\": $starting_timestamp/" \
    "$input_dir"/create_new_rollup.json

    # Extract the rollup manager address from the JSON file. .zkevm_agglayer_manageress is not available at the time of importing this script.
    # So a manual extraction of AgglayerManager is done here.
    # Even with multiple op stack deployments, the rollup manager address can be retrieved from combined.json because it must be constant.
    agglayer_manager="$(jq -r '.AgglayerManager' "${output_dir}/combined.json")"

    # Replace rollupManagerAddress with the extracted address
    sed -i "s|\"rollupManagerAddress\": \".*\"|\"rollupManagerAddress\":\"$agglayer_manager\"|" "$input_dir"/create_new_rollup.json

    # Replace AgglayerManager with the extracted address
    sed -i "s|\"polygonRollupManagerAddress\": \".*\"|\"polygonRollupManagerAddress\":\"$agglayer_manager\"|" "$input_dir"/add_rollup_type.json

    # This will require genesis.json and create_new_rollup.json to be correctly filled. We are using a pre-defined template for these.
    # The script and example files exist under https://github.com/0xPolygonHermez/zkevm-contracts/tree/v9.0.0-rc.5-pp/tools/createNewRollup
    # The templates being used here: create_new_rollup.json and genesis.json were directly referenced from the above source.
    rollupTypeID="{{ .l2_network_id }}"
    if [[ "$rollupTypeID" -eq 1 ]]; then
        echo "rollupID is 1. Running 4_createRollup.ts script"
    fi

    # The below method relies on https://github.com/0xPolygonHermez/zkevm-contracts/blob/v9.0.0-rc.5-pp/deployment/v2/4_createRollup.ts
    cp "$input_dir"/create_new_rollup.json "$contracts_dir"/deployment/v2/create_rollup_parameters.json
    npx hardhat run deployment/v2/4_createRollup.ts --network localhost 2>&1 | tee 05_create_sovereign_rollup.out

    # Save Rollup Information to a file.
    cast call --json --rpc-url "{{.l1_rpc_url}}" "$agglayer_manager" 'rollupIDToRollupData(uint32)(address,uint64,address,uint64,bytes32,uint64,uint64,uint64,uint64,uint64,uint64,uint8)' "{{.l2_network_id}}" | jq '{"sovereignRollupContract": .[0], "rollupChainID": .[1], "verifier": .[2], "forkID": .[3], "lastLocalExitRoot": .[4], "lastBatchSequenced": .[5], "lastVerifiedBatch": .[6], "_legacyLastPendingState": .[7], "_legacyLastPendingStateConsolidated": .[8], "lastVerifiedBatchBeforeUpgrade": .[9], "rollupTypeID": .[10], "rollupVerifierType": .[11]}' >"$contracts_dir"/sovereign-rollup-out.json

    # These are some accounts that we want to fund for operations for running claims.
    sovereign_admin_addr="{{.l2_sovereignadmin_address}}"
    sovereign_admin_private_key="{{.l2_sovereignadmin_private_key}}"
    aggoracle_addr="{{.l2_aggoracle_address}}"
    claimsponsor_addr="{{.l2_claimsponsor_address}}"

    rpc_url="{{.op_el_rpc_url}}"
    # This is the default prefunded account for the OP Network
    private_key=$(cast wallet private-key --mnemonic 'test test test test test test test test test test test junk')

    cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $sovereign_admin_addr
    cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $aggoracle_addr
    cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" $claimsponsor_addr

    # Contract Deployment Step
    cd "$contracts_dir" || exit

    echo "[profile.default]
    src = 'contracts'
    out = 'out'
    libs = ['node_modules']
    optimizer = true
    optimizer_runs = 200" > foundry.toml

    echo "Building contracts with forge build"
    forge build contracts/v2/sovereignChains/BridgeL2SovereignChain.sol contracts/v2/sovereignChains/GlobalExitRootManagerL2SovereignChain.sol
    bridge_impl_nonce=$(cast nonce --rpc-url $rpc_url $sovereign_admin_addr)
    bridge_impl_addr=$(cast compute-address --nonce "$bridge_impl_nonce" $sovereign_admin_addr | sed 's/.*: //')
    ger_impl_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 1)) $sovereign_admin_addr | sed 's/.*: //')
    ger_proxy_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 2)) $sovereign_admin_addr | sed 's/.*: //')
    bridge_proxy_addr=$(cast compute-address --nonce $((bridge_impl_nonce + 3)) $sovereign_admin_addr | sed 's/.*: //')

    _echo_ts "bridge_impl_addr: $bridge_impl_addr, bridge_proxy_addr: $bridge_proxy_addr, ger_impl_addr: $ger_impl_addr, ger_proxy_addr: $ger_proxy_addr"

    # This is one way to prefund the bridge. It can also be done with a deposit to some unclaimable network. This step is important and needs to be discussed
    cast send --legacy --value "{{.l2_funding_amount}}" --rpc-url $rpc_url --private-key "$private_key" "$bridge_proxy_addr"
    forge create --legacy --broadcast --rpc-url $rpc_url --private-key $sovereign_admin_private_key BridgeL2SovereignChain
    forge create --legacy --broadcast --rpc-url $rpc_url --private-key $sovereign_admin_private_key GlobalExitRootManagerL2SovereignChain --constructor-args "$bridge_proxy_addr"
    calldata=$(cast calldata 'initialize(address _globalExitRootUpdater, address _globalExitRootRemover)' $aggoracle_addr $sovereign_admin_addr)
    forge create --legacy --broadcast --rpc-url $rpc_url --private-key $sovereign_admin_private_key TransparentUpgradeableProxy --constructor-args "$ger_impl_addr" $sovereign_admin_addr "$calldata"

    initNetworkID="{{.l2_network_id}}"
    initGasTokenAddress="{{.gas_token_address}}"
    initGasTokenNetwork="{{.gas_token_network}}"
    initGlobalExitRootManager=$ger_proxy_addr
    initPolygonRollupManager=$agglayer_manager
    initGasTokenMetadata=0x
    initBridgeManager=$sovereign_admin_addr
    initSovereignWETHAddress="{{.sovereign_weth_address}}"
    initSovereignWETHAddressIsNotMintable="{{.sovereign_weth_address_not_mintable}}"

    calldata=$(cast calldata 'function initialize(uint32 _networkID, address _gasTokenAddress, uint32 _gasTokenNetwork, address _globalExitRootManager, address _polygonRollupManager, bytes _gasTokenMetadata, address _bridgeManager, address _sovereignWETHAddress, bool _sovereignWETHAddressIsNotMintable)' $initNetworkID "$initGasTokenAddress" $initGasTokenNetwork "$initGlobalExitRootManager" "$initPolygonRollupManager" $initGasTokenMetadata $initBridgeManager "$initSovereignWETHAddress" $initSovereignWETHAddressIsNotMintable)
    forge create --legacy --broadcast --rpc-url $rpc_url --private-key $sovereign_admin_private_key TransparentUpgradeableProxy --constructor-args "$bridge_impl_addr" $sovereign_admin_addr "$calldata"

    # Save the contract addresses to the sovereign-rollup-out.json file
    jq --arg bridge_impl_addr "$bridge_impl_addr" '. += {"bridge_impl_addr": $bridge_impl_addr}' "$contracts_dir"/sovereign-rollup-out.json >"$contracts_dir"/sovereign-rollup-out.json.temp && mv "$contracts_dir"/sovereign-rollup-out.json.temp "$contracts_dir"/sovereign-rollup-out.json
    jq --arg ger_impl_addr "$ger_impl_addr" '. += {"ger_impl_addr": $ger_impl_addr}' "$contracts_dir"/sovereign-rollup-out.json >"$contracts_dir"/sovereign-rollup-out.json.temp && mv "$contracts_dir"/sovereign-rollup-out.json.temp "$contracts_dir"/sovereign-rollup-out.json
    jq --arg ger_proxy_addr "$ger_proxy_addr" '. += {"ger_proxy_addr": $ger_proxy_addr}' "$contracts_dir"/sovereign-rollup-out.json >"$contracts_dir"/sovereign-rollup-out.json.temp && mv "$contracts_dir"/sovereign-rollup-out.json.temp "$contracts_dir"/sovereign-rollup-out.json
    jq --arg bridge_proxy_addr "$bridge_proxy_addr" '. += {"bridge_proxy_addr": $bridge_proxy_addr}' "$contracts_dir"/sovereign-rollup-out.json >"$contracts_dir"/sovereign-rollup-out.json.temp && mv "$contracts_dir"/sovereign-rollup-out.json.temp "$contracts_dir"/sovereign-rollup-out.json

    # Extract values from sovereign-rollup-out.json
    sovereignRollupContract=$(jq -r '.sovereignRollupContract' "$contracts_dir"/sovereign-rollup-out.json)
    rollupChainID=$(jq -r '.rollupChainID' "$contracts_dir"/sovereign-rollup-out.json)
    verifier=$(jq -r '.verifier' "$contracts_dir"/sovereign-rollup-out.json)
    forkID=$(jq -r '.forkID' "$contracts_dir"/sovereign-rollup-out.json)
    lastLocalExitRoot=$(jq -r '.lastLocalExitRoot' "$contracts_dir"/sovereign-rollup-out.json)
    lastBatchSequenced=$(jq -r '.lastBatchSequenced' "$contracts_dir"/sovereign-rollup-out.json)
    lastVerifiedBatch=$(jq -r '.lastVerifiedBatch' "$contracts_dir"/sovereign-rollup-out.json)
    _legacyLastPendingState=$(jq -r '._legacyLastPendingState' "$contracts_dir"/sovereign-rollup-out.json)
    _legacyLastPendingStateConsolidated=$(jq -r '._legacyLastPendingStateConsolidated' "$contracts_dir"/sovereign-rollup-out.json)
    lastVerifiedBatchBeforeUpgrade=$(jq -r '.lastVerifiedBatchBeforeUpgrade' "$contracts_dir"/sovereign-rollup-out.json)
    rollupTypeID=$(jq -r '.rollupTypeID' "$contracts_dir"/sovereign-rollup-out.json)
    rollupVerifierType=$(jq -r '.rollupVerifierType' "$contracts_dir"/sovereign-rollup-out.json)
    bridge_impl_addr=$(jq -r '.bridge_impl_addr' "$contracts_dir"/sovereign-rollup-out.json)
    ger_impl_addr=$(jq -r '.ger_impl_addr' "$contracts_dir"/sovereign-rollup-out.json)
    ger_proxy_addr=$(jq -r '.ger_proxy_addr' "$contracts_dir"/sovereign-rollup-out.json)
    bridge_proxy_addr=$(jq -r '.bridge_proxy_addr' "$contracts_dir"/sovereign-rollup-out.json)

    _echo_ts "bridge_impl_addr: $bridge_impl_addr, bridge_proxy_addr: $bridge_proxy_addr, ger_impl_addr: $ger_impl_addr, ger_proxy_addr: $ger_proxy_addr"

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
        '.LegacyAgglayerGERL2 = $ger_proxy_addr |
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
        "${output_dir}/combined.json" >"${output_dir}/combined.json.temp" &&
        mv "${output_dir}/combined.json.temp" "${output_dir}/combined.json"

    # Copy the updated combined.json to a new file with the deployment suffix
    cp "${output_dir}/combined.json" "${output_dir}/combined{{.deployment_suffix}}.json"

    # Contract addresses to extract from combined.json and check for bytecode
    # shellcheck disable=SC2034
    l1_contract_names=(
        "AgglayerManager"
        "AgglayerBridge"
        "AgglayerGER"
        "AgglayerGateway"
        "pessimisticVKeyRouteALGateway.verifier"
        "polTokenAddress"
        "zkEVMDeployerContract"
        "timelockContractAddress"
        "rollupAddress"
    )

    # shellcheck disable=SC2034
    l2_contract_names=(
        "polygonZkEVML2BridgeAddress"
        "LegacyAgglayerGERL2"
    )

    # JSON file to extract addresses from
    json_file="${output_dir}/combined.json"

    # shellcheck disable=SC2128
    l1_contract_addresses=$(_extract_addresses l1_contract_names "$json_file")
    # shellcheck disable=SC2128
    l2_contract_addresses=$(_extract_addresses l2_contract_names "$json_file")

    _check_deployed_contracts() {
        # shellcheck disable=SC2178
        local addresses=$1         # String of space-separated addresses
        local rpc_url=$2           # --rpc-url flag input for cast command
        
        # shellcheck disable=SC2128
        for addr in $addresses; do
            # Get bytecode using cast code with specified RPC URL
            if ! bytecode=$(cast code "$addr" --rpc-url "$rpc_url" 2>/dev/null); then
                echo "Address: $addr - Error checking address"
                continue
            fi
            
            if [[ $addr == "0x0000000000000000000000000000000000000000" ]]; then
                echo "Warning - The zero address was provide as one of the contracts"
                continue
            fi

            # Check if bytecode is non-zero
            if [ "$bytecode" = "0x" ] || [ -z "$bytecode" ]; then
                echo "Address: $addr - MISSING BYTECODE AT CONTRACT ADDRESS"
                exit 1  # Return non-zero exit code if no code is deployed
            else
                # Get bytecode length removing 0x prefix and counting hex chars
                byte_length=$(echo "$bytecode" | sed 's/^0x//' | wc -c)
                byte_length=$((byte_length / 2))  # Convert hex chars to bytes
                echo "Address: $addr - DEPLOYED (bytecode length: $byte_length bytes)"
            fi
        done
    }

    # Check deployed contracts
    _check_deployed_contracts "$l1_contract_addresses" "{{.l1_rpc_url}}"
    _check_deployed_contracts "$l2_contract_addresses" "{{.op_el_rpc_url}}"
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
elif [[ "$1" == "create_agglayer_rollup" ]]; then
    create_agglayer_rollup
elif [[ "$1" == "update_ger" ]]; then
    update_ger
elif [[ "$1" == "initialize_rollup" ]]; then
    initialize_rollup
elif [[ "$1" == "fund_addresses" ]]; then
    fund_addresses
elif [[ "$1" == "l2_legacy_fund_accounts" ]]; then
    l2_legacy_fund_accounts
elif [[ "$1" == "l2_contract_setup" ]]; then
    l2_contract_setup
elif [[ "$1" == "create_predeployed_op_genesis" ]]; then
    create_predeployed_op_genesis
elif [[ "$1" == "create_sovereign_rollup_predeployed" ]]; then
    create_sovereign_rollup_predeployed
elif [[ "$1" == "create_sovereign_rollup" ]]; then
    create_sovereign_rollup
else
    echo "Invalid argument: $1"
    exit 1
fi
