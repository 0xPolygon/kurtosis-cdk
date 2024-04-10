#!/bin/bash
# This script creates keystores for all the different zkevm/cdk node components.

# Create a go-ethereum style encrypted keystore.
create_geth_keystore() {
    local hexkey="$1"
    local password="$2"
    local keystore_name="$3"

    tmp_dir=$(mktemp -d)
    polycli parseethwallet --hexkey "$hexkey" --password "$password" --keystore "$tmp_dir"
    utc_file=$(find "$tmp_dir" -name 'UTC*')
    mv "$utc_file" "$keystore_name"
    chmod a+r "$keystore_name"
    rm -rf "$tmp_dir"
}

create_geth_keystore "sequencer.keystore"       "{{.zkevm_l2_sequencer_private_key}}"       "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "aggregator.keystore"      "{{.zkevm_l2_aggregator_private_key}}"      "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "claimtxmanager.keystore"  "{{.zkevm_l2_claimtxmanager_private_key}}"  "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "agglayer.keystore"        "{{.zkevm_l2_agglayer_private_key}}"        "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "dac.keystore"             "{{.zkevm_l2_dac_private_key}}"             "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "proofsigner.keystore"     "{{.zkevm_l2_proofsigner_private_key}}"     "{{.zkevm_l2_keystore_password}}"
