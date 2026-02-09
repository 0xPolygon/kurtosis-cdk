#!/bin/bash
set -euo pipefail

# End-to-end integration test for snapshot system
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENCLAVE_NAME="snapshot-test-e2e"
TEST_OUTPUT="$PROJECT_ROOT/test-snapshots"

echo "===== Snapshot E2E Test ====="
echo "This test will:"
echo "  1. Start a minimal Kurtosis enclave"
echo "  2. Create a snapshot"
echo "  3. Run the snapshot"
echo "  4. Verify chain operation"
echo "  5. Test statelessness (multiple runs)"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    if [ -d "$TEST_OUTPUT" ]; then
        cd "$TEST_OUTPUT"/snapshot-* 2>/dev/null && docker-compose down -v 2>/dev/null || true
    fi
    kurtosis enclave rm -f "$ENCLAVE_NAME" 2>/dev/null || true
    rm -rf "$TEST_OUTPUT"
    echo "Cleanup complete"
}
trap cleanup EXIT

# Step 1: Start Kurtosis enclave
echo "Step 1: Starting Kurtosis enclave..."

# Create temporary params file
PARAMS_FILE="$PROJECT_ROOT/test-params-$$.yaml"
cat > "$PARAMS_FILE" <<'EOF'
args:
  deploy_cdk_erigon_node: false
  deploy_cdk_bridge_infra: false
  deploy_zkevm_contracts_on_l1: false
  deploy_zkevm_node: false
  deploy_agglayer: false
  deploy_observability: false
  l1_preset: minimal
  l1_seconds_per_slot: 2
  l1_genesis_delay: 10
  l1_el_client_type: geth
  l1_cl_client_type: lighthouse
  additional_services: []
EOF

# Add debug API flag to enable debug_dumpBlock
echo "Enabling debug API on geth..."
if ! kurtosis run --enclave "$ENCLAVE_NAME" "$PROJECT_ROOT"; then
    echo "❌ FAILED: Could not start Kurtosis enclave"
    rm -f "$PARAMS_FILE"
    exit 1
fi
rm -f "$PARAMS_FILE"

echo "Waiting for chain to produce blocks..."
sleep 45

# Verify chain is running
GETH_RPC=$(kurtosis port print "$ENCLAVE_NAME" el-1-geth-lighthouse rpc | grep -oE 'http://[^[:space:]]+')
BLOCK_NUM=$(cast block-number --rpc-url "$GETH_RPC" 2>/dev/null || echo "0")
if [ "$BLOCK_NUM" = "0" ]; then
    echo "❌ FAILED: Chain not producing blocks"
    exit 1
fi
echo "✅ Chain running (block: $BLOCK_NUM)"
echo ""

# Step 2: Create snapshot
echo "Step 2: Creating snapshot..."
if ! "$SCRIPT_DIR/../snapshot.sh" "$ENCLAVE_NAME" --out "$TEST_OUTPUT"; then
    echo "❌ FAILED: Snapshot creation failed"
    exit 1
fi
echo "✅ Snapshot created"
echo ""

# Find snapshot directory
SNAPSHOT_DIR=$(find "$TEST_OUTPUT" -maxdepth 1 -type d -name "snapshot-$ENCLAVE_NAME-*" | head -1)
if [ -z "$SNAPSHOT_DIR" ]; then
    echo "❌ FAILED: Could not find snapshot directory"
    exit 1
fi
echo "Snapshot directory: $SNAPSHOT_DIR"

# Verify snapshot structure
echo "Verifying snapshot structure..."
REQUIRED_FILES=(
    "el/genesis.template.json"
    "el/alloc.json"
    "cl/config.yaml"
    "val/mnemonics.yaml"
    "docker-compose.yml"
    "tools/init.sh"
    "up.sh"
    "metadata.json"
)
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SNAPSHOT_DIR/$file" ]; then
        echo "❌ FAILED: Missing file: $file"
        exit 1
    fi
done
echo "✅ All required files present"
echo ""

# Step 3: Run snapshot (first time)
echo "Step 3: Running snapshot (first time)..."
cd "$SNAPSHOT_DIR"

# Clean and start
rm -rf runtime/*
if ! docker-compose up -d; then
    echo "❌ FAILED: docker-compose up failed"
    docker-compose logs
    exit 1
fi

# Wait for init
echo "Waiting for init to complete..."
sleep 10
if ! docker-compose ps | grep -q "snapshot-init.*exited (0)"; then
    echo "❌ FAILED: Init container did not complete successfully"
    docker-compose logs init
    exit 1
fi
echo "✅ Init completed"

# Wait for geth to be healthy
echo "Waiting for geth to be healthy..."
for i in {1..30}; do
    if docker-compose ps | grep -q "snapshot-geth.*healthy"; then
        break
    fi
    sleep 2
done

if ! docker-compose ps | grep -q "snapshot-geth.*healthy"; then
    echo "❌ FAILED: Geth did not become healthy"
    docker-compose logs geth
    exit 1
fi
echo "✅ Geth healthy"

# Step 4: Verify chain operation
echo "Step 4: Verifying chain operation..."
sleep 30  # Wait for blocks to be produced

SNAPSHOT_RPC="http://localhost:8545"
BLOCK_NUM=$(cast block-number --rpc-url "$SNAPSHOT_RPC" 2>/dev/null || echo "0")
if [ "$BLOCK_NUM" = "0" ]; then
    echo "❌ FAILED: Snapshot chain not producing blocks"
    docker-compose logs
    exit 1
fi
echo "✅ Snapshot chain producing blocks (block: $BLOCK_NUM)"

# Verify we can get block details
if ! cast block latest --rpc-url "$SNAPSHOT_RPC" &>/dev/null; then
    echo "❌ FAILED: Could not fetch block details"
    exit 1
fi
echo "✅ Can fetch block details"
echo ""

# Step 5: Test statelessness (restart with fresh genesis)
echo "Step 5: Testing statelessness (restart)..."
FIRST_GENESIS_TIME=$(jq -r '.timestamp' runtime/el_genesis.json)
echo "First genesis timestamp: $FIRST_GENESIS_TIME"

docker-compose down
sleep 5

echo "Starting again with fresh genesis..."
rm -rf runtime/*
docker-compose up -d
sleep 30

# Check new genesis time
SECOND_GENESIS_TIME=$(jq -r '.timestamp' runtime/el_genesis.json)
echo "Second genesis timestamp: $SECOND_GENESIS_TIME"

if [ "$FIRST_GENESIS_TIME" = "$SECOND_GENESIS_TIME" ]; then
    echo "❌ FAILED: Genesis timestamp did not change"
    exit 1
fi
echo "✅ Genesis timestamp changed (stateless)"

# Verify chain still works
sleep 30
BLOCK_NUM=$(cast block-number --rpc-url "$SNAPSHOT_RPC" 2>/dev/null || echo "0")
if [ "$BLOCK_NUM" = "0" ]; then
    echo "❌ FAILED: Chain not producing blocks after restart"
    exit 1
fi
echo "✅ Chain producing blocks after restart (block: $BLOCK_NUM)"
echo ""

# Cleanup
docker-compose down -v

echo "======================================"
echo "✅ ALL E2E TESTS PASSED!"
echo "======================================"
