#!/bin/bash

global_log_level="{{.global_log_level}}"
if [[ $global_log_level == "debug" ]]; then
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
        --rpc-url "$l2_rpc_url" \
        --private-key "{{.zkevm_l2_admin_private_key}}" \
        --value "{{.l2_funding_amount}}" \
        "$address"
}

if [[ -e "/opt/zkevm/.init-l2-complete{{.deployment_suffix}}.lock" ]]; then
    echo_ts "This script has already been executed"
    exit 1
fi

echo_ts "Waiting for the L2 RPC to be available"
wait_for_rpc_to_be_available
echo_ts "L2 RPC is now available"

echo_ts "Funding bridge autoclaimer account on l2"
fund_account_on_l2 "{{.zkevm_l2_claimtxmanager_address}}"

echo_ts "Funding accounts on l2"
accounts=$(
    polycli wallet inspect \
        --mnemonic "{{.l1_preallocated_mnemonic}}" \
        --addresses "{{.l2_accounts_to_fund}}"
)
echo "$accounts" | jq -r ".Addresses[].ETHAddress" | while read -r address; do
    fund_account_on_l2 "$address"
done

signer_address="0x3fab184622dc19b6109349b94811493bf2a45362"
gas_cost="0.01ether"
transaction="0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222"
deployer_address="0x4e59b44847b379578588920ca78fbf26c0b4956c"
l1_private_key=$(polycli wallet inspect --mnemonic "{{.l1_preallocated_mnemonic}}" | jq -r ".Addresses[0].HexPrivateKey")

echo_ts "Deploying deterministic deployment proxy on l1"
cast send \
    --rpc-url "{{.l1_rpc_url}}" \
    --private-key "$l1_private_key" \
    --value "$gas_cost" \
    "$signer_address"
cast publish --rpc-url "{{.l1_rpc_url}}" "$transaction"
if [[ $(cast code --rpc-url "{{.l1_rpc_url}}" $deployer_address) == "0x" ]]; then
    echo_ts "No code at expected l1 address: $deployer_address"
    exit 1;
fi

echo_ts "Deploying deterministic deployment proxy on l2"
cast send \
    --legacy \
    --rpc-url "$l2_rpc_url" \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --value "$gas_cost" \
    "$signer_address"
cast publish --rpc-url "$l2_rpc_url" "$transaction"
if [[ $(cast code --rpc-url "$l2_rpc_url" $deployer_address) == "0x" ]]; then
    echo_ts "No code at expected l2 address: $deployer_address"
    exit 1;
fi

# The contract setup is done!
touch "/opt/zkevm/.init-l2-complete{{.deployment_suffix}}.lock"
