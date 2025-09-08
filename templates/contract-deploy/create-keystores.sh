#!/bin/bash
# This script creates keystores for all the different zkevm/cdk node components.
set -e

# Create a go-ethereum style encrypted keystore.
create_geth_keystore() {
    local keystore_name="$1"
    local private_key="$2"
    local password="$3"

    temp_dir="/tmp/$keystore_name"
    output_dir="/opt/zkevm"
    mkdir -p "$temp_dir"
    cast wallet import --keystore-dir "$temp_dir" --private-key "$private_key" --unsafe-password "$password" "$keystore_name"
    jq < "$temp_dir/$keystore_name" > "$output_dir/$keystore_name"
    chmod a+r "$output_dir/$keystore_name"
    rm -rf "$temp_dir"
}

create_geth_keystore "sequencer.keystore"       "{{.zkevm_l2_sequencer_private_key}}"       "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "aggregator.keystore"      "{{.zkevm_l2_aggregator_private_key}}"      "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "claimtxmanager.keystore"  "{{.zkevm_l2_claimtxmanager_private_key}}"  "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "agglayer.keystore"        "{{.zkevm_l2_agglayer_private_key}}"        "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "dac.keystore"             "{{.zkevm_l2_dac_private_key}}"             "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "proofsigner.keystore"     "{{.zkevm_l2_proofsigner_private_key}}"     "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "aggoracle.keystore"       "{{.zkevm_l2_aggoracle_private_key}}"       "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "sovereignadmin.keystore"  "{{.zkevm_l2_sovereignadmin_private_key}}"  "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "claimsponsor.keystore"    "{{.zkevm_l2_claimsponsor_private_key}}"    "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "aggsendervalidator.keystore" "{{.zkevm_l2_aggsendervalidator_private_key}}" "{{.zkevm_l2_keystore_password}}"

# Generate multiple aggoracle keystores for committee members
# shellcheck disable=SC2050
if [[ "{{ .use_agg_oracle_committee }}" == "true" ]]; then
    MNEMONIC="lab code glass agree maid neutral vessel horror deny frequent favorite soft gate galaxy proof vintage once figure diary virtual scissors marble shrug drop"
    COMMITTEE_SIZE="{{ .agg_oracle_committee_total_members }}"

    if [[ "$COMMITTEE_SIZE" -ge 1 ]]; then
        for (( index=0; index<COMMITTEE_SIZE; index++ )); do
            aggoracle_private_key=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index $index)
            create_geth_keystore "aggoracle-$index.keystore" "$aggoracle_private_key" "{{.zkevm_l2_keystore_password}}"
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

        for (( index=0; index<VALIDATOR_COUNT; index++ )); do
            aggsendervalidator_private_key=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index $index)
            aggsender_validator_address=$(cast wallet address --private-key "$aggsendervalidator_private_key")

            create_geth_keystore "aggsendervalidator-$index.keystore" "$aggsendervalidator_private_key" "{{.zkevm_l2_keystore_password}}"

            json_output+='{"index":'$index',"address":"'$aggsender_validator_address'","private_key":"'$aggsendervalidator_private_key'"}'
            if [[ $index -lt $((VALIDATOR_COUNT-1)) ]]; then
                json_output+=","
            fi
        done

        json_output+="]"

        echo "$json_output" > /opt/zkevm/aggsender-validators.json

        jq --argfile vals /opt/zkevm/aggsender-validators.json '
            .aggchainParams.signers += (
                $vals
                | to_entries
                | map([ .value.address, "agg-sender validator \(.value.index)" ])
            )
            | .aggchainParams.threshold = ($vals | length)
        ' /opt/contract-deploy/create_new_rollup.json > /opt/contract-deploy/create_new_rollup.json.tmp && \
        mv /opt/contract-deploy/create_new_rollup.json.tmp /opt/contract-deploy/create_new_rollup.json
    fi
fi
