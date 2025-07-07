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
