#!/bin/bash
set -euo pipefail

# Verify that contracts from genesis alloc are properly deployed
# Usage: ./verify-genesis-code.sh <snapshot-directory>

SNAPSHOT_DIR="${1:?Please provide snapshot directory}"

if [ ! -d "$SNAPSHOT_DIR" ]; then
  echo "Error: Directory $SNAPSHOT_DIR does not exist"
  exit 1
fi

echo "=== Genesis Code Verification ==="
echo "Snapshot: $SNAPSHOT_DIR"
echo

# Check if geth is running
if ! docker ps --format '{{.Names}}' | grep -q '^snapshot-geth$'; then
  echo "Error: snapshot-geth container is not running"
  echo "Please start the snapshot first: cd $SNAPSHOT_DIR && docker compose up -d"
  exit 1
fi

# Get the genesis file
GENESIS_FILE="$SNAPSHOT_DIR/runtime/el_genesis.json"
if [ ! -f "$GENESIS_FILE" ]; then
  echo "Error: Genesis file not found at $GENESIS_FILE"
  exit 1
fi

echo "Extracting accounts with code from genesis..."

# Extract all accounts that have code (non-empty)
ACCOUNTS_WITH_CODE=$(jq -r '.alloc | to_entries | .[] | select(.value.code != null and .value.code != "" and .value.code != "0x") | .key' "$GENESIS_FILE")

TOTAL_ACCOUNTS=$(echo "$ACCOUNTS_WITH_CODE" | wc -l)
echo "Found $TOTAL_ACCOUNTS accounts with code in genesis"
echo

# Track results
VERIFIED=0
FAILED=0
FAILED_ADDRESSES=()

echo "Verifying deployed code..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for ADDRESS in $ACCOUNTS_WITH_CODE; do
  # Normalize address (ensure 0x prefix)
  if [[ ! "$ADDRESS" =~ ^0x ]]; then
    ADDRESS="0x$ADDRESS"
  fi

  # Get expected code from genesis
  EXPECTED_CODE=$(jq -r ".alloc[\"${ADDRESS#0x}\"].code // .alloc[\"$ADDRESS\"].code" "$GENESIS_FILE" 2>/dev/null)

  if [ -z "$EXPECTED_CODE" ] || [ "$EXPECTED_CODE" = "null" ]; then
    echo "⚠ Skipping $ADDRESS - code not found in genesis"
    continue
  fi

  # Get deployed code from chain
  RPC_RESULT=$(docker exec snapshot-geth sh -c "wget -qO- http://localhost:8545 --post-data='{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$ADDRESS\",\"latest\"],\"id\":1}' --header='Content-Type: application/json' 2>/dev/null" || echo '{"result":"0x"}')

  DEPLOYED_CODE=$(echo "$RPC_RESULT" | jq -r '.result // "0x"')

  # Normalize codes for comparison (remove 0x, convert to lowercase)
  EXPECTED_NORMALIZED=$(echo "$EXPECTED_CODE" | sed 's/^0x//' | tr '[:upper:]' '[:lower:]')
  DEPLOYED_NORMALIZED=$(echo "$DEPLOYED_CODE" | sed 's/^0x//' | tr '[:upper:]' '[:lower:]')

  # Compare
  if [ "$EXPECTED_NORMALIZED" = "$DEPLOYED_NORMALIZED" ]; then
    CODE_SIZE=${#EXPECTED_NORMALIZED}
    echo "✅ $ADDRESS - code matches (${CODE_SIZE} bytes)"
    ((VERIFIED++))
  else
    EXPECTED_SIZE=${#EXPECTED_NORMALIZED}
    DEPLOYED_SIZE=${#DEPLOYED_NORMALIZED}
    echo "❌ $ADDRESS - code MISMATCH!"
    echo "   Expected: ${EXPECTED_SIZE} bytes"
    echo "   Deployed: ${DEPLOYED_SIZE} bytes"
    if [ "$DEPLOYED_SIZE" = "0" ]; then
      echo "   Status: NO CODE DEPLOYED"
    fi
    ((FAILED++))
    FAILED_ADDRESSES+=("$ADDRESS")
  fi
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "=== SUMMARY ==="
echo "Total accounts checked: $TOTAL_ACCOUNTS"
echo "✅ Verified: $VERIFIED"
echo "❌ Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
  echo
  echo "Failed addresses:"
  for ADDR in "${FAILED_ADDRESSES[@]}"; do
    echo "  - $ADDR"
  done
  echo
  echo "❌ VERIFICATION FAILED"
  exit 1
else
  echo
  echo "✅ ALL GENESIS CODE VERIFIED SUCCESSFULLY"
  exit 0
fi
