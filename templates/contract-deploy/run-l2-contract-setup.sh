#!/bin/bash

log_level="{{.log_level}}"
if [[ $log_level == "debug" ]]; then
    set -x
fi

echo_ts() {
    local green="\e[32m"
    local end_color="\e[0m"
    local timestamp
    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")

    echo -e "$green$timestamp$end_color $1" >&2
}

wait_for_rpc_to_be_available() {
    local counter=0
    local max_retries=20
    local retry_interval=5

    until cast send --legacy \
                    --rpc-url "$l2_rpc_url" \
                    --private-key "{{.zkevm_l2_admin_private_key}}" \
                    --value 0 "{{.zkevm_l2_sequencer_address}}" &> /dev/null; do
        ((counter++))
        echo_ts "Can't send L2 transfers yet... Retrying ($counter)..."
        if [[ $counter -ge $max_retries ]]; then
            echo_ts "Exceeded maximum retry attempts. Exiting."
            exit 1
        fi
        sleep $retry_interval
    done
}

fund_account_on_l2() {
    local address="$1"
    echo_ts "Funding $address"
    cast send \
        --legacy \
        --async \
        --nonce "$account_nonce" \
        --rpc-url "$l2_rpc_url" \
        --private-key "{{.zkevm_l2_admin_private_key}}" \
        --value "{{.l2_funding_amount}}" \
        "$address"
    account_nonce="$((account_nonce + 1))"
}

if [[ -e "/opt/zkevm/.init-l2-complete{{.deployment_suffix}}.lock" ]]; then
    echo_ts "This script has already been executed"
    exit 1
fi

if [[ -z "$l2_rpc_url" ]]; then
    echo "Error: l2_rpc_url is not set. Exiting."
    exit 1
fi

echo_ts "Waiting for the L2 RPC to be available"
wait_for_rpc_to_be_available
echo_ts "L2 RPC is now available"

eth_address="$(cast wallet address --private-key "{{.zkevm_l2_admin_private_key}}")"
account_nonce="$(cast nonce --rpc-url "$l2_rpc_url" "$eth_address")"

echo_ts "Funding bridge autoclaimer account on l2"
fund_account_on_l2 "{{.zkevm_l2_claimtxmanager_address}}"

echo_ts "Funding claim sponsor account on l2"
fund_account_on_l2 "{{.zkevm_l2_claimsponsor_address}}"

# Only fund the claim tx manager address if l2 contracts are not being deployed.
if [[ "$1" != "true" ]]; then
    exit
fi

echo_ts "Funding accounts on l2"
for (( i = 0; i < "{{.l2_accounts_to_fund}}"; i++ )); do
    address=$(cast wallet address --mnemonic "{{.l1_preallocated_mnemonic}}" --mnemonic-index "$i")
    fund_account_on_l2 "$address"
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
    echo_ts "Deploying deterministic deployment proxy on l2"
    cast send \
        --legacy \
        --rpc-url "$l2_rpc_url" \
        --private-key "{{.zkevm_l2_admin_private_key}}" \
        --value "$gas_cost" \
        --nonce "$account_nonce" \
        "$signer_address"
    cast publish --rpc-url "$l2_rpc_url" "$transaction"
    if [[ $(cast code --rpc-url "$l2_rpc_url" $deployer_address) == "0x" ]]; then
        echo_ts "No code at expected l2 address: $deployer_address"
        exit 1;
    fi
else
    echo_ts "Skipping deployment of deterministic deployment proxy on l2"
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
    echo_ts "Deploying lxly bridge and call on l1"
    export DEPLOYER_PRIVATE_KEY="$l1_private_key"
    forge script script/DeployInitBridgeAndCall.s.sol --rpc-url "{{.l1_rpc_url}}" --legacy --broadcast
else
    echo_ts "Skipping deployment of lxly bridge and call on l1"
fi

# shellcheck disable=SC2078
if [[ "{{.l2_deploy_lxly_bridge_and_call}}" ]]; then
    echo_ts "Deploying lxly bridge and call on l2"
    export DEPLOYER_PRIVATE_KEY="{{.zkevm_l2_admin_private_key}}"
    forge script script/DeployInitBridgeAndCall.s.sol --rpc-url "$l2_rpc_url" --legacy --broadcast
else
    echo_ts "Skipping deployment of lxly bridge and call on l2"
fi

# The contract setup is done!
touch "/opt/zkevm/.init-l2-complete{{.deployment_suffix}}.lock"
