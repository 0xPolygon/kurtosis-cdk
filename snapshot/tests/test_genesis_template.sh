#!/bin/bash
set -euo pipefail

# Test genesis template creation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

echo "Testing genesis template creation..."

# Create test alloc
cat > "$TEST_DIR/alloc.json" <<EOF
{
  "0x1111111111111111111111111111111111111111": {
    "balance": "0x1000000000000000000"
  },
  "0x2222222222222222222222222222222222222222": {
    "balance": "0x2000000000000000000",
    "nonce": "0x5"
  }
}
EOF

# Create genesis template
bash "$SCRIPT_DIR/../scripts/create_genesis_template.sh" \
    "$TEST_DIR/alloc.json" \
    "$TEST_DIR/genesis.json" \
    1337

# Verify structure
echo "Verifying genesis structure..."

# Check it's valid JSON
if ! jq empty "$TEST_DIR/genesis.json" 2>/dev/null; then
    echo "❌ FAILED: Genesis is not valid JSON"
    exit 1
fi

# Check chainId
CHAIN_ID=$(jq '.config.chainId' "$TEST_DIR/genesis.json")
if [ "$CHAIN_ID" != "1337" ]; then
    echo "❌ FAILED: Expected chainId 1337, got $CHAIN_ID"
    exit 1
fi

# Check timestamp placeholder (jq returns with quotes)
TIMESTAMP=$(jq -r '.timestamp' "$TEST_DIR/genesis.json")
if [ "$TIMESTAMP" != "TIMESTAMP_PLACEHOLDER" ]; then
    echo "❌ FAILED: Expected TIMESTAMP_PLACEHOLDER, got $TIMESTAMP"
    exit 1
fi

# Check alloc was injected
ALLOC_COUNT=$(jq '.alloc | length' "$TEST_DIR/genesis.json")
if [ "$ALLOC_COUNT" != "2" ]; then
    echo "❌ FAILED: Expected 2 accounts in alloc, got $ALLOC_COUNT"
    exit 1
fi

# Check specific account
BALANCE=$(jq -r '.alloc["0x1111111111111111111111111111111111111111"].balance' "$TEST_DIR/genesis.json")
if [ "$BALANCE" != "0x1000000000000000000" ]; then
    echo "❌ FAILED: Account balance mismatch"
    exit 1
fi

echo "✅ All genesis template tests passed!"
