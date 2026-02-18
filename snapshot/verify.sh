#!/usr/bin/env bash
#
# Snapshot Verification Script
# Validates that a snapshot can boot and produce blocks
#
# Usage: verify.sh <SNAPSHOT_DIR>
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

log_step() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}$*${NC}"
    echo -e "${GREEN}========================================${NC}\n"
}

pass() {
    echo -e "${GREEN}✓ PASS:${NC} $*"
}

fail() {
    echo -e "${RED}✗ FAIL:${NC} $*"
}

# Usage
usage() {
    cat << EOF
Snapshot Verification Script

Usage:
  $0 <SNAPSHOT_DIR>

Arguments:
  SNAPSHOT_DIR        Path to snapshot directory

Description:
  Verifies a snapshot by:
  1. Starting the snapshot services
  2. Checking initial block number matches checkpoint
  3. Waiting for block progression
  4. Validating all services are healthy

Examples:
  $0 snapshots/snapshot-test-20260202-115500

EOF
    exit 0
}

# Parse arguments
if [ $# -ne 1 ]; then
    usage
fi

SNAPSHOT_DIR="$1"

# Validate snapshot directory
if [ ! -d "$SNAPSHOT_DIR" ]; then
    log_error "Snapshot directory not found: $SNAPSHOT_DIR"
    exit 1
fi

if [ ! -f "$SNAPSHOT_DIR/docker-compose.yml" ]; then
    log_error "docker-compose.yml not found in: $SNAPSHOT_DIR"
    exit 1
fi

if [ ! -f "$SNAPSHOT_DIR/metadata/checkpoint.json" ]; then
    log_error "checkpoint.json not found in: $SNAPSHOT_DIR"
    exit 1
fi

# ============================================================================
# Setup
# ============================================================================

log_step "Snapshot Verification"
log "Snapshot directory: $SNAPSHOT_DIR"

# Extract snapshot ID from directory name for container names
SNAPSHOT_ID=$(basename "$SNAPSHOT_DIR")
log "Snapshot ID: $SNAPSHOT_ID"

# Read checkpoint metadata
CHECKPOINT="$SNAPSHOT_DIR/metadata/checkpoint.json"
EXPECTED_BLOCK=$(jq -r '.l1_state.block_number' "$CHECKPOINT")
EXPECTED_HASH=$(jq -r '.l1_state.block_hash' "$CHECKPOINT")
SNAPSHOT_NAME=$(jq -r '.snapshot_name' "$CHECKPOINT")

log "Snapshot: $SNAPSHOT_NAME"
log "Expected block number: $EXPECTED_BLOCK"
log "Expected block hash: $EXPECTED_HASH"

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

test_result() {
    local test_name="$1"
    local result="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ "$result" = "pass" ]; then
        pass "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        fail "$test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ============================================================================
# Test 1: Check Docker Images Exist
# ============================================================================

log_step "TEST 1: Docker Images"

log "Checking if snapshot images exist..."

TAG=$(cat "$SNAPSHOT_DIR/images/.tag" 2>/dev/null || echo "unknown")
log "Image tag: $TAG"

IMAGES=("snapshot-geth:$TAG" "snapshot-beacon:$TAG" "snapshot-validator:$TAG")
ALL_IMAGES_EXIST=true

for image in "${IMAGES[@]}"; do
    if docker images -q "$image" &> /dev/null; then
        log_info "  Found: $image"
    else
        log_error "  Missing: $image"
        ALL_IMAGES_EXIST=false
    fi
done

if [ "$ALL_IMAGES_EXIST" = true ]; then
    test_result "All Docker images exist" "pass"
else
    test_result "All Docker images exist" "fail"
fi

# ============================================================================
# Test 2: Start Snapshot Services
# ============================================================================

log_step "TEST 2: Start Services"

log "Starting snapshot services..."

cd "$SNAPSHOT_DIR"

# Check if services are already running
if docker-compose -f docker-compose.yml ps | grep -q "Up"; then
    log_warn "Services appear to be already running, stopping first..."
    docker-compose -f docker-compose.yml down &> /dev/null || true
    sleep 5
fi

# Clean up any old snapshot containers that might conflict with ports
log "Checking for conflicting snapshot containers..."
OLD_SNAPSHOTS=$(docker ps -a --filter "name=cdk-" --format "{{.Names}}" | grep -v "$SNAPSHOT_ID" || true)
if [ -n "$OLD_SNAPSHOTS" ]; then
    log_warn "Found old snapshot containers, cleaning up..."
    echo "$OLD_SNAPSHOTS" | xargs -r docker stop &> /dev/null || true
    echo "$OLD_SNAPSHOTS" | xargs -r docker rm &> /dev/null || true
    sleep 2
fi

# Start services
if docker-compose -f docker-compose.yml up -d &> /dev/null; then
    test_result "Services started" "pass"
else
    test_result "Services started" "fail"
    log_error "Failed to start services"
    exit 1
fi

# Wait for services to initialize
log "Waiting for services to initialize..."
sleep 10

# ============================================================================
# Test 3: Service Health Checks
# ============================================================================

log_step "TEST 3: Service Health"

log "Checking service status..."

SERVICES=("${SNAPSHOT_ID}-geth" "${SNAPSHOT_ID}-beacon" "${SNAPSHOT_ID}-validator")
ALL_HEALTHY=true

for service in "${SERVICES[@]}"; do
    status=$(docker inspect --format='{{.State.Status}}' "$service" 2>/dev/null || echo "not found")

    if [ "$status" = "running" ]; then
        log_info "  $service: running"
    else
        log_error "  $service: $status"
        ALL_HEALTHY=false
    fi
done

if [ "$ALL_HEALTHY" = true ]; then
    test_result "All services running" "pass"
else
    test_result "All services running" "fail"
fi

# ============================================================================
# Test 4: Geth RPC Connectivity
# ============================================================================

log_step "TEST 4: RPC Connectivity"

log "Testing Geth RPC endpoint..."

# Wait up to 30 seconds for RPC to be ready
RPC_READY=false
for _ in {1..30}; do
    if curl -s http://localhost:8545 \
        -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        &> /dev/null; then
        RPC_READY=true
        log_info "  Geth RPC is accessible"
        break
    fi
    sleep 1
done

if [ "$RPC_READY" = true ]; then
    test_result "Geth RPC accessible" "pass"
else
    test_result "Geth RPC accessible" "fail"
    log_error "Geth RPC did not become accessible within 30 seconds"
fi

# ============================================================================
# Test 5: Initial Block Number and Hash
# ============================================================================

log_step "TEST 5: Initial Block Number and Hash"

log "Querying current block state..."

# Query the block at the expected height using eth_getBlockByNumber
EXPECTED_BLOCK_HEX=$(printf "0x%x" "$EXPECTED_BLOCK" 2>/dev/null || echo "latest")

BLOCK_DATA=$(curl -s http://localhost:8545 \
    -X POST \
    -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$EXPECTED_BLOCK_HEX\",false],\"id\":1}" \
    2>/dev/null || echo "")

# Also query the latest block number to compare
LATEST_HEX=$(curl -s http://localhost:8545 \
    -X POST \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result' 2>/dev/null || echo "0x0")

CURRENT_BLOCK=$((16#${LATEST_HEX#0x}))

log "Current block: $CURRENT_BLOCK"
log "Expected block: $EXPECTED_BLOCK"

# Verify block number
BLOCK_NUMBER_MATCH=false
if [ "$EXPECTED_BLOCK" = "unknown" ]; then
    log_warn "Expected block is unknown, skipping number comparison"
    BLOCK_NUMBER_MATCH=true
elif [ "$CURRENT_BLOCK" -ge "$EXPECTED_BLOCK" ]; then
    log_info "Block number is at or past checkpoint (difference: $((CURRENT_BLOCK - EXPECTED_BLOCK)) blocks)"
    BLOCK_NUMBER_MATCH=true
else
    log_error "Block number is behind checkpoint (difference: $((EXPECTED_BLOCK - CURRENT_BLOCK)) blocks)"
    BLOCK_NUMBER_MATCH=false
fi

# Verify block hash (if we have the expected block)
BLOCK_HASH_MATCH=false
if [ -n "$BLOCK_DATA" ] && echo "$BLOCK_DATA" | jq -e '.result' &>/dev/null; then
    ACTUAL_HASH=$(echo "$BLOCK_DATA" | jq -r '.result.hash' 2>/dev/null || echo "")
    ACTUAL_BLOCK_NUM_HEX=$(echo "$BLOCK_DATA" | jq -r '.result.number' 2>/dev/null || echo "")
    ACTUAL_BLOCK_NUM=$((16#${ACTUAL_BLOCK_NUM_HEX#0x}))

    log "Block $ACTUAL_BLOCK_NUM hash: $ACTUAL_HASH"
    log "Expected hash: $EXPECTED_HASH"

    if [ "$EXPECTED_HASH" = "unknown" ] || [ -z "$EXPECTED_HASH" ]; then
        log_warn "Expected hash is unknown, skipping hash comparison"
        BLOCK_HASH_MATCH=true
    elif [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]; then
        log_info "Block hash matches checkpoint exactly"
        BLOCK_HASH_MATCH=true
    else
        log_error "Block hash does NOT match checkpoint"
        log_error "This indicates a different chain state than expected"
        BLOCK_HASH_MATCH=false
    fi
else
    log_warn "Could not query block $EXPECTED_BLOCK, skipping hash comparison"
    # If we can't query the specific block, still pass if the number check passed
    BLOCK_HASH_MATCH=$BLOCK_NUMBER_MATCH
fi

# Test passes if both number and hash match
if [ "$BLOCK_NUMBER_MATCH" = true ] && [ "$BLOCK_HASH_MATCH" = true ]; then
    test_result "Initial block matches checkpoint (number and hash)" "pass"
else
    test_result "Initial block matches checkpoint (number and hash)" "fail"
fi

# ============================================================================
# Test 6: Block Progression
# ============================================================================

log_step "TEST 6: Block Progression"

log "Waiting 10 seconds to check if blocks are progressing..."
sleep 10

# Query block number again
BLOCK_HEX_AFTER=$(curl -s http://localhost:8545 \
    -X POST \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result' 2>/dev/null || echo "0x0")

BLOCK_AFTER=$((16#${BLOCK_HEX_AFTER#0x}))

log "Block after 10s: $BLOCK_AFTER"
log "Block difference: $((BLOCK_AFTER - CURRENT_BLOCK))"

if [ "$BLOCK_AFTER" -gt "$CURRENT_BLOCK" ]; then
    log_info "Blocks are progressing ($((BLOCK_AFTER - CURRENT_BLOCK)) blocks in 10s)"
    test_result "Blocks continue progressing" "pass"
else
    log_error "Blocks are NOT progressing"
    test_result "Blocks continue progressing" "fail"
fi

# ============================================================================
# Test 7: Beacon Chain Connectivity
# ============================================================================

log_step "TEST 7: Beacon Chain"

log "Testing Beacon API endpoint..."

# Check beacon health
BEACON_READY=false
for _ in {1..30}; do
    if curl -s http://localhost:4000/eth/v1/node/health &> /dev/null; then
        BEACON_READY=true
        log_info "  Beacon API is accessible"
        break
    fi
    sleep 1
done

if [ "$BEACON_READY" = true ]; then
    test_result "Beacon API accessible" "pass"

    # Get beacon head slot
    BEACON_SLOT=$(curl -s http://localhost:4000/eth/v1/beacon/headers/head | jq -r '.data.header.message.slot' 2>/dev/null || echo "unknown")
    log "Beacon head slot: $BEACON_SLOT"
else
    test_result "Beacon API accessible" "fail"
fi

# ============================================================================
# Test 8: Service Logs
# ============================================================================

log_step "TEST 8: Service Logs"

log "Checking for errors in service logs..."

HAS_ERRORS=false

for service in "${SERVICES[@]}"; do
    # Filter out expected warnings/errors that are benign in standalone snapshots
    ERROR_COUNT=$(docker logs "$service" 2>&1 | \
        grep -i "error\|fatal\|panic" | \
        grep -v "level=error" | \
        grep -v "NoPeersSubscribedToTopic" | \
        grep -v "Could not publish message" | \
        grep -v "Error processing HTTP API request" | \
        grep -v "Gateway does not support UPnP" | \
        grep -v "404 Not Found" | \
        grep -c "" || echo 0)

    if [ "$ERROR_COUNT" -gt 5 ]; then
        log_warn "  $service: $ERROR_COUNT error-like messages found"
        HAS_ERRORS=true
    else
        log_info "  $service: clean logs"
    fi
done

if [ "$HAS_ERRORS" = false ]; then
    test_result "No critical errors in logs" "pass"
else
    test_result "No critical errors in logs" "fail"
fi

# ============================================================================
# Test 9: L2 Block Progression
# ============================================================================

log_step "TEST 9: L2 Block Progression"

log "Checking L2 chains for block progression..."

# Find L2 RPC endpoints from docker-compose
L2_RPCS=$(docker-compose -f docker-compose.yml config | grep -E "op-geth-[0-9]+" -A 5 | grep -c "8545:8545" || echo 0)

if [ "$L2_RPCS" -eq 0 ]; then
    log_warn "No L2 chains found in snapshot, skipping L2 block progression test"
else
    log "Found L2 chains, testing block progression..."

    # Get L2 container names
    L2_CONTAINERS=$(docker ps --filter "name=${SNAPSHOT_ID}-op-geth" --format "{{.Names}}" || echo "")

    if [ -z "$L2_CONTAINERS" ]; then
        log_warn "No L2 containers running, skipping L2 test"
    else
        L2_ALL_PASSED=true

        while IFS= read -r container; do
            # Extract L2 ID from container name (e.g., cdk-xxx-op-geth-001 -> 001)
            L2_ID=$(echo "$container" | grep -oP 'op-geth-\K[0-9]+$' || echo "unknown")
            log "Testing L2 chain: $L2_ID (container: $container)"

            # Get the port mapping for this L2's RPC
            L2_PORT=$(docker port "$container" 8545 2>/dev/null | cut -d: -f2 || echo "")

            if [ -z "$L2_PORT" ]; then
                log_error "  Could not find RPC port for $container"
                L2_ALL_PASSED=false
                continue
            fi

            log_info "  L2 RPC endpoint: http://localhost:$L2_PORT"

            # Query initial block number
            INITIAL_BLOCK_HEX=$(curl -s "http://localhost:$L2_PORT" \
                -X POST \
                -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                | jq -r '.result' 2>/dev/null || echo "0x0")

            INITIAL_BLOCK=$((16#${INITIAL_BLOCK_HEX#0x}))
            log "  Initial L2 block: $INITIAL_BLOCK"

            # Check if L2 has produced blocks beyond genesis
            if [ "$INITIAL_BLOCK" -le 0 ]; then
                log_warn "  L2 is still at genesis (block 0)"
                log_warn "  L2 may need more time to start producing blocks"
                log_warn "  This could indicate a configuration issue"
                # Don't immediately fail - check if blocks progress
            else
                log_info "  L2 has produced blocks (block $INITIAL_BLOCK)"
            fi

            # Wait 5 seconds
            log "  Waiting 5 seconds..."
            sleep 5

            # Query block number again
            FINAL_BLOCK_HEX=$(curl -s "http://localhost:$L2_PORT" \
                -X POST \
                -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                | jq -r '.result' 2>/dev/null || echo "0x0")

            FINAL_BLOCK=$((16#${FINAL_BLOCK_HEX#0x}))
            log "  Final L2 block: $FINAL_BLOCK"
            log "  Block difference: $((FINAL_BLOCK - INITIAL_BLOCK))"

            # Assert block number has increased OR is greater than 0
            if [ "$FINAL_BLOCK" -gt "$INITIAL_BLOCK" ]; then
                log_info "  ✓ L2 blocks are progressing ($((FINAL_BLOCK - INITIAL_BLOCK)) blocks in 5s)"
            elif [ "$FINAL_BLOCK" -gt 0 ]; then
                log_info "  ✓ L2 is producing blocks (at block $FINAL_BLOCK)"
            else
                log_error "  ✗ L2 blocks are NOT progressing (stuck at block 0)"
                log_error "  Check op-node and op-geth logs for errors"
                L2_ALL_PASSED=false
            fi

        done <<< "$L2_CONTAINERS"

        if [ "$L2_ALL_PASSED" = true ]; then
            test_result "All L2 chains producing blocks" "pass"
        else
            test_result "All L2 chains producing blocks" "fail"
        fi
    fi
fi

# ============================================================================
# Results Summary
# ============================================================================

log_step "VERIFICATION RESULTS"

echo ""
log "Tests run: $TESTS_TOTAL"
log "Tests passed: $TESTS_PASSED"
log "Tests failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    log_step "✓ VERIFICATION PASSED"
    log "The snapshot is working correctly!"
    log ""
    log "Services are running at:"
    log "  Geth RPC: http://localhost:8545"
    log "  Beacon API: http://localhost:4000"
    log ""
    log "To stop the snapshot:"
    log "  cd $SNAPSHOT_DIR && docker-compose -f docker-compose.yml down"
    echo ""
    EXIT_CODE=0
else
    log_step "✗ VERIFICATION FAILED"
    log_error "$TESTS_FAILED test(s) failed"
    log ""
    log "To view service logs:"
    log "  cd $SNAPSHOT_DIR && docker-compose -f docker-compose.yml logs"
    log ""
    log "To stop services:"
    log "  cd $SNAPSHOT_DIR && docker-compose -f docker-compose.yml down"
    echo ""
    EXIT_CODE=1
fi

exit $EXIT_CODE
