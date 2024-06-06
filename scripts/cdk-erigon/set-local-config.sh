#!/bin/bash
set -e

# Download the cdk-erigon node configuration files.
rm -r /tmp/zkevm
mkdir -p data/cdk-erigon-rpc-local-l1
kurtosis files download cdk-v1 cdk-erigon-node-chain-config /tmp/zkevm
kurtosis files download cdk-v1 cdk-erigon-node-chain-allocs /tmp/zkevm
cp /tmp/zkevm/dynamic-kurtosis-conf.json data/cdk-erigon-rpc-local-l1
cp /tmp/zkevm/dynamic-kurtosis-allocs.json data/cdk-erigon-rpc-local-l1

# Extract the zkevm contract addresses.
contract_addresses="$(kurtosis service exec cdk-v1 contracts-001 "cat /opt/zkevm/combined.json" | tail -n +2 | jq)"

# Set the zkevm contract addresses in params.yml
zkevm_rollup_address="$(echo "$contract_addresses" | jq --raw-output .rollupAddress)"
# shellcheck disable=SC2016
yq -Y --in-place --arg a "$zkevm_rollup_address" '.args.zkevm_rollup_address = $a' params.yml

zkevm_rollup_manager_address="$(echo "$contract_addresses" | jq --raw-output .polygonRollupManagerAddress)"
# shellcheck disable=SC2016
yq -Y --in-place --arg a "$zkevm_rollup_manager_address" '.args.zkevm_rollup_manager_address = $a' params.yml

zkevm_global_exit_root_address="$(echo "$contract_addresses" | jq --raw-output .polygonZkEVMGlobalExitRootAddress)"
# shellcheck disable=SC2016
yq -Y --in-place --arg a "$zkevm_global_exit_root_address" '.args.zkevm_global_exit_root_address = $a' params.yml

pol_token_address="$(echo "$contract_addresses" | jq --raw-output .polTokenAddress)"
# shellcheck disable=SC2016
yq -Y --in-place --arg a "$pol_token_address" '.args.pol_token_address = $a' params.yml

zkevm_rollup_manager_block_number="$(echo "$contract_addresses" | jq --raw-output .deploymentRollupManagerBlockNumber)"
# shellcheck disable=SC2016
yq -Y --in-place --arg a "$zkevm_rollup_manager_block_number" '.args.zkevm_rollup_manager_block_number = $a' params.yml
