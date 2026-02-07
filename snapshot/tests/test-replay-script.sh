#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/tmp"
mkdir -p "$TEST_DIR"

echo "=========================================="
echo "Testing Replay Script Generation"
echo "=========================================="

# Create test transaction log
cat > "$TEST_DIR/test-tx.jsonl" << EOF
{"tx_number":0,"method":"eth_sendRawTransaction","raw_tx":"0x1234","timestamp":1234567890}
{"tx_number":1,"method":"eth_sendRawTransaction","raw_tx":"0x5678","timestamp":1234567891}
EOF

echo "Test transaction log created with 2 transactions"

# Generate replay script
echo "Generating replay script..."
"$SCRIPT_DIR/../scripts/generate-replay-script.sh" \
    "$TEST_DIR/test-tx.jsonl" \
    "$TEST_DIR/replay.sh"

echo "Verifying generated script..."

# Verify file exists
if [ ! -f "$TEST_DIR/replay.sh" ]; then
    echo "❌ FAIL: Script not generated"
    exit 1
fi
echo "✓ Script file exists"

# Verify executable
if [ ! -x "$TEST_DIR/replay.sh" ]; then
    echo "❌ FAIL: Script not executable"
    exit 1
fi
echo "✓ Script is executable"

# Verify transaction 0x1234 is present
if ! grep -q "0x1234" "$TEST_DIR/replay.sh"; then
    echo "❌ FAIL: TX 0x1234 missing"
    exit 1
fi
echo "✓ TX 0x1234 found"

# Verify transaction 0x5678 is present
if ! grep -q "0x5678" "$TEST_DIR/replay.sh"; then
    echo "❌ FAIL: TX 0x5678 missing"
    exit 1
fi
echo "✓ TX 0x5678 found"

# Verify completion marker command is present
if ! grep -q ".replay_complete" "$TEST_DIR/replay.sh"; then
    echo "❌ FAIL: Completion marker command missing"
    exit 1
fi
echo "✓ Completion marker command present"

# Verify send_tx function calls
if ! grep -q "send_tx 0" "$TEST_DIR/replay.sh"; then
    echo "❌ FAIL: send_tx 0 call missing"
    exit 1
fi
echo "✓ send_tx function calls present"

# Cleanup
rm -rf "$TEST_DIR"

echo ""
echo "=========================================="
echo "✅ PASS: Replay script generation works"
echo "=========================================="
