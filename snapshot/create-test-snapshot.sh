#!/bin/bash
set -euo pipefail

# Helper script to create a snapshot from the snapshot-test enclave
# Run this after the enclave has fully started and is producing blocks

ENCLAVE_NAME="snapshot-test"
OUTPUT_DIR="./test-snapshots"

echo "===== Snapshot Test Script ====="
echo ""

# Check if enclave exists
if ! kurtosis enclave inspect "$ENCLAVE_NAME" &>/dev/null; then
    echo "❌ Error: Enclave '$ENCLAVE_NAME' not found"
    echo ""
    echo "Start the enclave first:"
    echo "  kurtosis run --enclave $ENCLAVE_NAME . --args-file snapshot-test-params.yaml"
    exit 1
fi

echo "✅ Enclave '$ENCLAVE_NAME' found"
echo ""

# Check if L1 is producing blocks
echo "Checking if L1 is producing blocks..."
GETH_RPC=$(kurtosis port print "$ENCLAVE_NAME" el-1-geth-lighthouse rpc | grep -oE 'http://[^[:space:]]+')
BLOCK_NUM=$(cast block-number --rpc-url "$GETH_RPC" 2>/dev/null || echo "0")

if [ "$BLOCK_NUM" = "0" ]; then
    echo "⚠️  Warning: L1 at block 0 - chain may still be initializing"
    echo "   Waiting 60 seconds for blocks..."
    sleep 60
    BLOCK_NUM=$(cast block-number --rpc-url "$GETH_RPC" 2>/dev/null || echo "0")
fi

if [ "$BLOCK_NUM" = "0" ]; then
    echo "❌ Error: L1 not producing blocks yet"
    echo "   Please wait for the enclave to fully start"
    echo ""
    echo "Check status with: kurtosis enclave inspect $ENCLAVE_NAME"
    exit 1
fi

echo "✅ L1 producing blocks (current: $BLOCK_NUM)"
echo ""

# Verify debug API is enabled
echo "Verifying debug API is enabled..."
if ! cast rpc --rpc-url "$GETH_RPC" debug_dumpBlock "1" >/dev/null 2>&1; then
    echo "❌ Error: debug API not available"
    echo "   The debug_dumpBlock method is not accessible"
    exit 1
fi

echo "✅ Debug API enabled and responding"
echo ""

# Create snapshot
echo "Creating snapshot..."
echo ""
./snapshot/snapshot.sh "$ENCLAVE_NAME" --out "$OUTPUT_DIR"

# Check if snapshot was created
SNAPSHOT_DIR=$(find "$OUTPUT_DIR" -maxdepth 1 -type d -name "snapshot-$ENCLAVE_NAME-*" | head -1)
if [ -z "$SNAPSHOT_DIR" ]; then
    echo "❌ Error: Snapshot not created"
    exit 1
fi

echo ""
echo "======================================"
echo "✅ Snapshot created successfully!"
echo "======================================"
echo ""
echo "Snapshot location: $SNAPSHOT_DIR"
echo ""
echo "To run the snapshot:"
echo "  cd $SNAPSHOT_DIR"
echo "  ./up.sh"
echo ""
echo "To verify it works:"
echo "  cast block-number --rpc-url http://localhost:8545"
echo ""
