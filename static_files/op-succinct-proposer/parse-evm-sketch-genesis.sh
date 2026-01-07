#!/bin/bash
# This script takes the genesis.json from L1 geth and parses it to the below format
# {
#   "config": {
#     "chainId": <YOUR CHAIN ID>,
#     "homesteadBlock": 0,
#     "daoForkBlock": 0,
#     "daoForkSupport": true,
#     "eip150Block": 0,
#     "eip155Block": 0,
#     "eip158Block": 0,
#     "byzantiumBlock": 0,
#     "constantinopleBlock": 0,
#     "petersburgBlock": 0,
#     "istanbulBlock": 0,
#     "muirGlacierBlock": 0,
#     "berlinBlock": 0,
#     "londonBlock": 0,
#     "mergeNetsplitBlock": 0,
#     "terminalTotalDifficulty": "17000000000000000",
#     "shanghaiTime": 0,
#     "cancunTime": 0,
#     "pragueTime": 1749737513
#   }
# }
set -x

# Change to the working directory
cd /opt/op-succinct || { echo "Error: Failed to change to /opt/op-succinct"; exit 1; }

# genesis_file="/opt/op-succinct/genesis.json"
chain_id="{{.l2_chain_id}}"
genesis_file="/opt/op-succinct/genesis-$chain_id.json"

# Check if genesis.json exists
if [[ ! -f "$genesis_file" ]]; then
    echo "Error: $genesis_file not found"
    exit 1
fi

# Add "config" section
jq '{"config": .config}' "$genesis_file" > /opt/op-succinct/evm-sketch-genesis.json

# Verify the extraction
# shellcheck disable=SC2181
if [[ $? -eq 0 ]]; then
    echo "Config section extracted to evm-sketch-genesis.json"
else
    echo "Error: Failed to extract config section"
    exit 1
fi