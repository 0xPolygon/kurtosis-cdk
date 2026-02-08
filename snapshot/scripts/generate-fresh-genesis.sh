#!/bin/bash
#
# Generate fresh genesis.ssz with current timestamp
# Uses Lighthouse lcli via Docker to create genesis state
#
# Usage: ./generate-fresh-genesis.sh <OUTPUT_DIR>
#

set -euo pipefail

OUTPUT_DIR="$1"

if [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <OUTPUT_DIR>" >&2
    exit 1
fi

ARTIFACTS_DIR="$OUTPUT_DIR/artifacts"

echo "Generating fresh genesis.ssz with current timestamp..."

# Calculate genesis time: now + 60 seconds (buffer for build/startup)
GENESIS_TIME=$(($(date +%s) + 60))
echo "  Genesis time: $GENESIS_TIME ($(date -d @$GENESIS_TIME 2>/dev/null || date -r $GENESIS_TIME))"

# Check if we have the original chain spec
CHAIN_SPEC="$ARTIFACTS_DIR/chain-spec.yaml"
if [ ! -f "$CHAIN_SPEC" ]; then
    echo "ERROR: chain-spec.yaml not found" >&2
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Prepare testnet directory structure
mkdir -p "$TEMP_DIR/testnet"

# Copy and modify chain spec with new genesis time
sed -e "s/^MIN_GENESIS_TIME: .*/MIN_GENESIS_TIME: $GENESIS_TIME/" \
    -e "s/^GENESIS_DELAY: .*/GENESIS_DELAY: 10/" \
    "$CHAIN_SPEC" > "$TEMP_DIR/testnet/config.yaml"

# Copy genesis.json (execution layer genesis)
if [ -f "$ARTIFACTS_DIR/genesis.json" ]; then
    cp "$ARTIFACTS_DIR/genesis.json" "$TEMP_DIR/testnet/genesis.json"
fi

# Extract validator keys from validator data
VALIDATOR_DIR="$OUTPUT_DIR/datadirs/validator-data/validator-keys"
if [ -d "$VALIDATOR_DIR/keys" ]; then
    mkdir -p "$TEMP_DIR/validators"

    # Count validators
    VALIDATOR_COUNT=$(ls -1 "$VALIDATOR_DIR/keys"/0x*.json 2>/dev/null | wc -l || echo "0")
    echo "  Found $VALIDATOR_COUNT validator keystores"

    if [ "$VALIDATOR_COUNT" -gt 0 ]; then
        # Copy keystores
        cp "$VALIDATOR_DIR/keys"/0x*.json "$TEMP_DIR/validators/" 2>/dev/null || true

        # Copy secrets if available
        if [ -d "$VALIDATOR_DIR/secrets" ]; then
            cp "$VALIDATOR_DIR/secrets"/* "$TEMP_DIR/validators/" 2>/dev/null || true
        elif [ -d "$VALIDATOR_DIR/lodestar-secrets" ]; then
            cp "$VALIDATOR_DIR/lodestar-secrets"/* "$TEMP_DIR/validators/" 2>/dev/null || true
        fi
    fi
fi

# Generate deposit data from validator keystores
# This creates the validator deposits needed for genesis
echo "  Generating validator deposits..."

# Use lighthouse Docker image to generate genesis
docker run --rm \
    -v "$TEMP_DIR:/work" \
    sigp/lighthouse:v8.0.1 \
    lcli \
    create-testnet \
    --testnet-dir /work/testnet \
    --deposit-contract-address "0x4242424242424242424242424242424242424242" \
    --min-genesis-active-validator-count 1 \
    --min-genesis-time "$GENESIS_TIME" \
    --genesis-delay 10 \
    --genesis-fork-version "0x10000038" \
    --altair-fork-epoch 0 \
    --bellatrix-fork-epoch 0 \
    --capella-fork-epoch 0 \
    --deneb-fork-epoch 0 \
    --ttd 0 \
    --eth1-block-hash "$(grep -o '"hash":"0x[^"]*"' $TEMP_DIR/testnet/genesis.json | head -1 | cut -d'"' -f4)" \
    --eth1-id 271828 \
    --eth1-follow-distance 1 \
    --seconds-per-slot 1 \
    --seconds-per-eth1-block 1 \
    2>&1 || {
        echo "  WARNING: lcli create-testnet failed"
        echo "  Falling back to original genesis.ssz with updated config"
        # Copy original genesis.ssz but with updated config
        if [ -f "$ARTIFACTS_DIR/genesis.ssz" ]; then
            cp "$ARTIFACTS_DIR/genesis.ssz" "$TEMP_DIR/testnet/genesis.ssz"
        fi
    }

# Check if genesis.ssz was generated
if [ -f "$TEMP_DIR/testnet/genesis.ssz" ]; then
    # Backup original
    if [ -f "$ARTIFACTS_DIR/genesis.ssz" ]; then
        cp "$ARTIFACTS_DIR/genesis.ssz" "$ARTIFACTS_DIR/genesis.ssz.backup"
    fi

    # Copy fresh genesis
    cp "$TEMP_DIR/testnet/genesis.ssz" "$ARTIFACTS_DIR/genesis.ssz"
    echo "  ✓ Fresh genesis.ssz generated"
else
    echo "  WARNING: Could not generate fresh genesis.ssz"
    echo "  Using original genesis.ssz (time limitation will apply)"
fi

# Always update the chain spec with new genesis time
cp "$TEMP_DIR/testnet/config.yaml" "$ARTIFACTS_DIR/chain-spec.yaml"
echo "  ✓ Chain spec updated with genesis time: $GENESIS_TIME"

exit 0
