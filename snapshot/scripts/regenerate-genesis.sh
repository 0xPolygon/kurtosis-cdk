#!/bin/bash
#
# Regenerate genesis.ssz with fresh timestamp
# This solves the PoS genesis time limitation
#
# Usage: ./regenerate-genesis.sh <OUTPUT_DIR>
#

set -euo pipefail

OUTPUT_DIR="$1"

if [ -z "$OUTPUT_DIR" ] || [ ! -d "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <SNAPSHOT_OUTPUT_DIR>" >&2
    echo "Example: $0 ./snapshots/cdk-20260207-195445" >&2
    exit 1
fi

echo "Regenerating genesis.ssz with fresh timestamp..."

# Calculate new genesis time: now + 30 seconds
NEW_GENESIS_TIME=$(($(date +%s) + 30))
echo "New genesis time: $NEW_GENESIS_TIME ($(date -d @$NEW_GENESIS_TIME 2>/dev/null || date -r $NEW_GENESIS_TIME))"

# Check if lcli is available
if ! command -v lcli &> /dev/null; then
    echo "ERROR: lcli (Lighthouse CLI) not found"
    echo ""
    echo "Please install Lighthouse:"
    echo "  cargo install --git https://github.com/sigp/lighthouse.git lcli --locked"
    echo ""
    echo "Or use Docker:"
    echo "  docker run --rm -v \$PWD:/data sigp/lighthouse:latest lcli ..."
    exit 1
fi

# Update chain spec with new genesis time
CHAIN_SPEC="$OUTPUT_DIR/artifacts/chain-spec.yaml"
if [ ! -f "$CHAIN_SPEC" ]; then
    echo "ERROR: chain-spec.yaml not found at $CHAIN_SPEC"
    exit 1
fi

# Create temporary modified spec
TMP_SPEC=$(mktemp)
sed "s/^MIN_GENESIS_TIME: .*/MIN_GENESIS_TIME: $NEW_GENESIS_TIME/" "$CHAIN_SPEC" > "$TMP_SPEC"

echo "Generating fresh genesis.ssz..."

# Use lcli to generate new genesis state
# Note: This requires validator deposits to be present
lcli new-testnet \
    --spec mainnet \
    --testnet-dir "$OUTPUT_DIR/artifacts/fresh-genesis" \
    --min-genesis-time "$NEW_GENESIS_TIME" \
    --genesis-delay 30

# Replace old genesis.ssz with new one
if [ -f "$OUTPUT_DIR/artifacts/fresh-genesis/genesis.ssz" ]; then
    cp "$OUTPUT_DIR/artifacts/fresh-genesis/genesis.ssz" "$OUTPUT_DIR/artifacts/genesis.ssz"
    echo "✓ genesis.ssz regenerated successfully"

    # Rebuild beacon image with new genesis
    echo "Rebuilding beacon image..."
    cd "$OUTPUT_DIR"
    # Note: You'll need to rebuild the beacon Docker image after this
    echo ""
    echo "IMPORTANT: Rebuild the beacon Docker image with:"
    echo "  cd $OUTPUT_DIR"
    echo "  docker build -t snapshot-beacon:latest images/beacon/"
    echo ""
    echo "Then restart the snapshot:"
    echo "  docker-compose down && docker-compose up -d"
else
    echo "ERROR: Failed to generate fresh genesis.ssz"
    rm -f "$TMP_SPEC"
    exit 1
fi

rm -f "$TMP_SPEC"

echo "Done!"
