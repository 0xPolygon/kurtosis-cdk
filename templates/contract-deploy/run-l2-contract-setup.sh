#!/bin/bash

global_log_level="{{.global_log_level}}"
if [[ $global_log_level == "debug" ]]; then
    set -x
fi

echo_ts() {
    local green="\e[32m"
    local end_color="\e[0m"
    local timestamp
    timestamp=$(date + "[%Y-%m-%d %H:%M:%S]")

    echo -e "$green$timestamp$end_color $1" >&2
}

wait_for_rpc_to_be_available() {
    local counter=0
    local max_retries=20
    local retry_interval=5

    until cast send --legacy \
                    --rpc-url "{{.l2_rpc_url}}" \
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
        --rpc-url "{{.l2_rpc_url}}" \
        --private-key "{{.zkevm_l2_admin_private_key}}" \
        --value "{{.l2_funding_amount}}" \
        "$address"
}

if [[ -e "/opt/zkevm/.init-complete{{.deployment_suffix}}.lock" ]]; then
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
echo "$accounts" | jq -r '.Addresses[].ETHAddress' | while read -r address; do
    fund_account_on_l2 "$address"
done

# The contract setup is done!
touch "/opt/zkevm/.init-complete{{.deployment_suffix}}.lock"
