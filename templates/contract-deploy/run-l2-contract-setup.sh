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
echo "$accounts" | jq -r ".Addresses[].ETHAddress" | while read -r address; do
    fund_account_on_l2 "$address"
done

echo_ts "Building deterministic deployment proxy"
git clone https://github.com/Arachnid/deterministic-deployment-proxy.git \
    /opt/deterministic-deployment-proxy \
    --branch "{{.deterministic_deployment_proxy_branch}}"
cd /opt/deterministic-deployment-proxy || exit 1
npm ci
npm run build

signer_address="0x$(jq -r '.signerAddress' output/deployment.json)"
gas_price=$(jq -r '.gasPrice' output/deployment.json)
gas_limit=$(jq -r '.gasLimit' output/deployment.json)
gas_cost=$((gas_price * gas_limit))
transaction="0x$(jq -r '.transaction' output/deployment.json)"
deployer_address="0x$(jq -r '.address' output/deployment.json)"
l1_private_key=$(
    polycli wallet inspect \
        --mnemonic "{{.l1_preallocated_mnemonic}}" \
        --addresses 1 \
        | jq -r ".Addresses[].HexPrivateKey"
)

echo_ts "Deploying deterministic deployment proxy on l1"
cast send \
    --rpc-url "{{.l1_rpc_url}}" \
    --private-key "$l1_private_key" \
    --value "$gas_cost" \
    "$signer_address"
cast publish --rpc-url "{{.l1_rpc_url}}" "$transaction"

echo_ts "Deploying deterministic deployment proxy on l2"
cast send \
    --legacy \
    --rpc-url "{{.l2_rpc_url}}" \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    --value "$gas_cost" \
    "$signer_address"
cast publish --rpc-url "{{.l2_rpc_url}}" "$transaction"

contract_method_signature="banana()(uint8)"
expected="42"
salt="0x0000000000000000000000000000000000000000000000000000000000000000"
# contract: pragma solidity 0.5.8; contract Apple {function banana() external pure returns (uint8) {return 42;}}
bytecode="6080604052348015600f57600080fd5b5060848061001e6000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c8063c3cafc6f14602d575b600080fd5b6033604f565b604051808260ff1660ff16815260200191505060405180910390f35b6000602a90509056fea165627a7a72305820ab7651cb86b8c1487590004c2444f26ae30077a6b96c6bc62dda37f1328539250029"
contract_address=$(cast create2 --salt $salt --init-code $bytecode)

echo_ts "Testing deterministic deployment proxy on l1"
cast send \
    --legacy \
    --rpc-url "{{.l1_rpc_url}}" \
    --private-key "$l1_private_key" \
    "$deployer_address" \
    "$salt$bytecode"
l1_actual=$(cast call --rpc-url "{{.l1_rpc_url}}" "$contract_address" "$contract_method_signature")
if [ "$expected" != "$l1_actual" ]; then
    echo_ts "Failed to deploy deterministic deployment proxy on l1 (expected: $expected, actual $l1_actual)"
    exit 1
fi

echo_ts "Testing deterministic deployment proxy on l2"
cast send \
    --legacy \
    --rpc-url "{{.l2_rpc_url}}" \
    --private-key "{{.zkevm_l2_admin_private_key}}" \
    "$deployer_address" \
    "$salt$bytecode"
l2_actual=$(cast call --rpc-url "{{.l2_rpc_url}}" "$contract_address" "$contract_method_signature")
if [ "$expected" != "$l2_actual" ]; then
    echo_ts "Failed to deploy deterministic deployment proxy on l2 (expected: $expected, actual $l2_actual)"
    exit 1
fi

# The contract setup is done!
touch "/opt/zkevm/.init-complete{{.deployment_suffix}}.lock"