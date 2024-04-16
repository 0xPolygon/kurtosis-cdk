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
    polycli parseethwallet --hexkey "$private_key" --password "$password" --keystore "$temp_dir"
    mv "$temp_dir"/UTC* "$output_dir/$keystore_name"
    jq < "$output_dir/$keystore_name" > "$output_dir/$keystore_name.new"
    mv "$output_dir/$keystore_name.new" "$output_dir/$keystore_name"
    chmod a+r "$output_dir/$keystore_name"
    rm -rf "$temp_dir"
}

create_geth_keystore "sequencer.keystore"       "{{.zkevm_l2_sequencer_private_key}}"       "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "aggregator.keystore"      "{{.zkevm_l2_aggregator_private_key}}"      "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "claimtxmanager.keystore"  "{{.zkevm_l2_claimtxmanager_private_key}}"  "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "agglayer.keystore"        "{{.zkevm_l2_agglayer_private_key}}"        "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "dac.keystore"             "{{.zkevm_l2_dac_private_key}}"             "{{.zkevm_l2_keystore_password}}"
create_geth_keystore "proofsigner.keystore"     "{{.zkevm_l2_proofsigner_private_key}}"     "{{.zkevm_l2_keystore_password}}"
