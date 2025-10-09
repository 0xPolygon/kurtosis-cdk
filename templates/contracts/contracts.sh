#!/bin/bash
input_dir="/opt/input"
output_dir="/opt/output"
keystores_dir="/opt/keystores"

# Create a go-ethereum style encrypted keystore.
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

# main handler, execute function according to parameter received
if [[ "$1" == "create_keystores" ]]; then
    create_keystores
elif [[ "$1" == "configure_contract_container_custom_genesis" ]]; then
    configure_contract_container_custom_genesis
else
    echo "Invalid argument: $1"
    exit 1
fi
