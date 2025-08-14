#!/usr/bin/env bash

# Exit on error
set -e

# Validate required environment variables
if [[ -z "$RPC_URL" ]]; then
    echo "Error: RPC_URL environment variable is not set."
    exit 1
fi

if [[ -z "$ADDRESSES_TO_FUND" ]]; then
    echo "Error: ADDRESSES_TO_FUND environment variable is not set."
    exit 1
fi

if [[ -z "$L2_FUNDING_AMOUNT" ]]; then
    echo "Error: L2_FUNDING_AMOUNT environment variable is not set."
    exit 1
fi

# The layer1 url when use local
EXPECT_URL="http://op-el-1-op-geth-op-node$DEPLOYMENT_SUFFIX:8545"

# Set private key based on RPC_URL
if [[ "$RPC_URL" == "$EXPECT_URL" ]]; then
    # Default optimism-package preallocated mnemonic
    if ! private_key=$(cast wallet private-key --mnemonic "test test test test test test test test test test test junk" 2>/dev/null) || [[ -z "$private_key" ]]; then
        echo "Error: Failed to derive private key from mnemonic."
        exit 1
    fi
else
    if [[ -z "$L1_PREALLOCATED_MNEMONIC" ]]; then
        echo "Error: L1_PREALLOCATED_MNEMONIC environment variable is not set for non-default RPC."
        exit 1
    fi
    if ! private_key=$(cast wallet private-key --mnemonic "$L1_PREALLOCATED_MNEMONIC" 2>/dev/null) || [[ -z "$private_key" ]]; then
        echo "Error: Failed to derive private key from mnemonic."
        exit 1
    fi
fi

# Fund addresses
IFS=';' read -ra addresses <<<"$ADDRESSES_TO_FUND"

# Validate addresses and fund them
for address in "${addresses[@]}"; do
    # Basic address validation (ensure it’s a valid Ethereum address)
    if ! [[ "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Error: Invalid Ethereum address: $address"
        continue
    fi

    echo "Funding $address with $L2_FUNDING_AMOUNT"
    if ! cast send \
        --private-key "$private_key" \
        --rpc-url "$RPC_URL" \
        --value "$L2_FUNDING_AMOUNT" \
        "$address" >/dev/null 2>&1; then
        echo "Error: Failed to fund $address"
    else
        echo "Successfully funded $address"
    fi
done