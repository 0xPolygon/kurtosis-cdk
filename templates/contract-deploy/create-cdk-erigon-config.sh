#!/bin/bash
# This script will use combined.json and genesis.json to generate CDK erigon configuration files.

echo_ts() {
    green="\e[32m"
    end_color="\e[0m"

    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo -e "$green$timestamp$end_color $1" >&2
}


# 1. Create cdk-erigon allocs file.
echo_ts "Creating dynamic-kurtosis-allocs.json..."

# Use jq to transform the genesis file into an allocs file for cdk-erigon.
jq_script='
.genesis | map({
  (.address): {
    contractName: (if .contractName == "" then null else .contractName end),
    balance: (if .balance == "" then null else .balance end),
    nonce: (if .nonce == "" then null else .nonce end),
    code: (if .bytecode == "" then null else .bytecode end),
    storage: (if .storage == null or .storage == {} then null else (.storage | to_entries | sort_by(.key) | from_entries) end)
  }
}) | add'

if ! output_json=$(jq "$jq_script" /opt/zkevm/genesis.json); then
    echo_ts "Error processing JSON with jq"
    exit 1
fi

if ! echo "$output_json" | jq . > /opt/zkevm/dynamic-kurtosis-allocs.json; then
    echo_ts "Error creating the dynamic kurtosis allocs config"
    exit 1
fi
echo_ts "- dynamic-kurtosis-allocs.json generated"


# 2. Create cdk-erigon config file.
echo_ts "Creating dynamic-kurtosis-conf.json..."
jq \
    --null-input \
    --slurpfile genesis /opt/zkevm/genesis.json \
    --slurpfile combined /opt/zkevm/combined.json \
    '{
        root: $genesis[0].root,
        timestamp: ($combined[0].firstBatchData.timestamp | tonumber),
        gasLimit: 0,
        difficulty: 0
    }' > /opt/zkevm/dynamic-kurtosis-conf.json

if [[ ! -s /opt/zkevm/dynamic-kurtosis-conf.json ]]; then
    echo_ts "Error creating the dynamic kurtosis config"
    exit 1
fi

echo_ts "- dynamic-kurtosis-conf.json generated"


# 3. Create cdk-erigon first batch config.
# zkevm.initial-batch.config
jq '.firstBatchData' /opt/zkevm/combined.json > /opt/zkevm/first-batch-config.json

if [[ ! -s /opt/zkevm/first-batch-config.json ]]; then
    echo_ts "Error creating the first batch config"
    exit 1
fi

echo_ts "- first-batch-config.json generated"
