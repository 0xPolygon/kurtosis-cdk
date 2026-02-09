#!/bin/bash
set -uo pipefail
# Note: Not using 'set -e' to allow script to continue through all accounts

# Verify that contracts from genesis alloc are properly deployed
# Usage: ./verify-genesis-code-v2.sh <snapshot-directory>

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
  exit 1
fi

# Get the genesis file
GENESIS_FILE="$SNAPSHOT_DIR/runtime/el_genesis.json"
if [ ! -f "$GENESIS_FILE" ]; then
  echo "Error: Genesis file not found at $GENESIS_FILE"
  exit 1
fi

echo "Extracting accounts with code from genesis..."

# Use python to parse JSON (more reliable than jq with shell escaping)
python3 - "$GENESIS_FILE" > /tmp/accounts_with_code.txt <<'PYTHON_EOF'
import json
import sys

with open(sys.argv[1], 'r') as f:
    genesis = json.load(f)

accounts_with_code = []
for addr, data in genesis.get('alloc', {}).items():
    code = data.get('code', '')
    if code and code not in ['', '0x']:
        # Normalize address
        if not addr.startswith('0x'):
            addr = '0x' + addr
        accounts_with_code.append(addr.lower())

for addr in accounts_with_code:
    print(addr)
PYTHON_EOF

TOTAL_ACCOUNTS=$(wc -l < /tmp/accounts_with_code.txt)
echo "Found $TOTAL_ACCOUNTS accounts with code in genesis"
echo

if [ "$TOTAL_ACCOUNTS" -eq 0 ]; then
  echo "No accounts with code found in genesis"
  exit 0
fi

# Track results
VERIFIED=0
FAILED=0

echo "Verifying deployed code..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

while IFS= read -r ADDRESS; do
  # Get expected code from genesis
  EXPECTED_CODE=$(python3 <<PYTHON_EOF
import json
import sys
with open('$GENESIS_FILE', 'r') as f:
    genesis = json.load(f)
addr = '$ADDRESS'.lower().replace('0x', '')
code = genesis.get('alloc', {}).get(addr, {}).get('code', '')
if not code:
    # Try with 0x prefix
    code = genesis.get('alloc', {}).get('0x' + addr, {}).get('code', '')
print(code if code else '0x')
PYTHON_EOF
)

  if [ "$EXPECTED_CODE" = "0x" ] || [ -z "$EXPECTED_CODE" ]; then
    echo "⚠ Skipping $ADDRESS - no code in genesis"
    continue
  fi

  # Get deployed code from chain
  RPC_RESULT=$(docker exec snapshot-geth sh -c "wget -qO- http://localhost:8545 --post-data='{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$ADDRESS\",\"latest\"],\"id\":1}' --header='Content-Type: application/json' 2>/dev/null" || echo '{"result":"0x"}')

  DEPLOYED_CODE=$(echo "$RPC_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('result', '0x'))")

  # Normalize for comparison
  EXPECTED_NORM=$(echo "$EXPECTED_CODE" | tr '[:upper:]' '[:lower:]')
  DEPLOYED_NORM=$(echo "$DEPLOYED_CODE" | tr '[:upper:]' '[:lower:]')

  # Compare
  if [ "$EXPECTED_NORM" = "$DEPLOYED_NORM" ]; then
    CODE_SIZE=$((${#EXPECTED_CODE} - 2))  # Subtract 2 for '0x'
    echo "✅ $ADDRESS - code matches ($CODE_SIZE hex chars)"
    ((VERIFIED++))
  else
    EXPECTED_SIZE=$((${#EXPECTED_CODE} - 2))
    DEPLOYED_SIZE=$((${#DEPLOYED_CODE} - 2))
    echo "❌ $ADDRESS - code MISMATCH!"
    echo "   Expected: $EXPECTED_SIZE hex chars"
    echo "   Deployed: $DEPLOYED_SIZE hex chars"
    ((FAILED++))
  fi
done < /tmp/accounts_with_code.txt

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "=== SUMMARY ==="
echo "Total accounts checked: $TOTAL_ACCOUNTS"
echo "✅ Verified: $VERIFIED"
echo "❌ Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
  echo
  echo "❌ VERIFICATION FAILED - Some contracts don't match"
  exit 1
else
  echo
  echo "✅ ALL GENESIS CODE VERIFIED SUCCESSFULLY"
  exit 0
fi
