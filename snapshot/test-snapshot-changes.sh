#!/usr/bin/env bash
#
# Test script to verify all snapshot changes are working correctly
# Tests: network fix, bridge service component, and port configuration
#
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}✓${NC} $*"
}

error() {
    echo -e "${RED}✗${NC} $*"
}

warn() {
    echo -e "${YELLOW}!${NC} $*"
}

FAILED_TESTS=0
PASSED_TESTS=0

echo "=========================================="
echo "Testing Snapshot Changes"
echo "=========================================="
echo ""

# Test 1: Network configuration in generate-compose.sh
echo "Test 1: Checking network configuration..."
if grep -q "external: true" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh; then
    log "Network is marked as external in generate-compose.sh"
    ((PASSED_TESTS++))
else
    error "Network is NOT marked as external in generate-compose.sh"
    ((FAILED_TESTS++))
fi
echo ""

# Test 2: Bridge service component in aggkit
echo "Test 2: Checking bridge service component..."
if grep -q "bridgeservice" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh; then
    log "Bridge service component is included in aggkit"
    ((PASSED_TESTS++))
else
    error "Bridge service component is NOT included in aggkit"
    ((FAILED_TESTS++))
fi
echo ""

# Test 3: Bridge service port configuration
echo "Test 3: Checking bridge service port (8080)..."
if grep -q "L2_AGGKIT_BRIDGE_PORT" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh; then
    log "Bridge service port is configured in generate-compose.sh"
    ((PASSED_TESTS++))
else
    error "Bridge service port is NOT configured in generate-compose.sh"
    ((FAILED_TESTS++))
fi
echo ""

# Test 4: Bridge service port in summary.json generation
echo "Test 4: Checking bridge service in summary.json generation..."
if grep -q "bridge_service" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-summary.sh; then
    log "Bridge service is included in summary.json generation"
    ((PASSED_TESTS++))
else
    error "Bridge service is NOT included in summary.json generation"
    ((FAILED_TESTS++))
fi
echo ""

# Test 5: Network creation in start script
echo "Test 5: Checking network creation logic..."
if grep -q "docker network create" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh; then
    log "Network creation logic is present in start script"
    ((PASSED_TESTS++))
else
    error "Network creation logic is NOT present in start script"
    ((FAILED_TESTS++))
fi
echo ""

# Test 6: Network removal in stop script
echo "Test 6: Checking network removal logic..."
if grep -q "docker network rm" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh; then
    log "Network removal logic is present in stop script"
    ((PASSED_TESTS++))
else
    error "Network removal logic is NOT present in stop script"
    ((FAILED_TESTS++))
fi
echo ""

# Test 7: Check latest snapshot (if any)
echo "Test 7: Checking most recent snapshot..."
LATEST_SNAPSHOT=$(ls -t /home/aigent/kurtosis-cdk/snapshots/cdk-* 2>/dev/null | head -1 || echo "")

if [ -n "$LATEST_SNAPSHOT" ] && [ -f "$LATEST_SNAPSHOT/docker-compose.yml" ]; then
    SNAPSHOT_NAME=$(basename "$LATEST_SNAPSHOT")
    echo "  Found: $SNAPSHOT_NAME"

    # Check network configuration
    if grep -q "external: true" "$LATEST_SNAPSHOT/docker-compose.yml"; then
        log "Snapshot has network marked as external"
        ((PASSED_TESTS++))
    else
        error "Snapshot does NOT have network marked as external"
        ((FAILED_TESTS++))
    fi

    # Check bridge service component
    if grep -q "bridgeservice" "$LATEST_SNAPSHOT/docker-compose.yml"; then
        log "Snapshot has bridgeservice component in aggkit"
        ((PASSED_TESTS++))
    else
        warn "Snapshot does NOT have bridgeservice component (may not have L2 networks)"
    fi

    # Check bridge service port
    if grep -q "8080.*Bridge Service" "$LATEST_SNAPSHOT/docker-compose.yml"; then
        log "Snapshot has bridge service port exposed"
        ((PASSED_TESTS++))
    else
        warn "Snapshot does NOT have bridge service port (may not have L2 networks)"
    fi

    # Check all services have network configured
    SERVICE_COUNT=$(grep -c "container_name:" "$LATEST_SNAPSHOT/docker-compose.yml" || echo "0")
    NETWORK_COUNT=$(grep -c "networks:" "$LATEST_SNAPSHOT/docker-compose.yml" || echo "0")
    # Subtract 1 for the networks: section at the end
    NETWORK_COUNT=$((NETWORK_COUNT - 1))

    if [ "$SERVICE_COUNT" -eq "$NETWORK_COUNT" ]; then
        log "All $SERVICE_COUNT services have network configured"
        ((PASSED_TESTS++))
    else
        error "Not all services have network configured ($NETWORK_COUNT/$SERVICE_COUNT)"
        ((FAILED_TESTS++))
    fi
else
    warn "No snapshots found. Generate a snapshot to test the complete implementation."
fi
echo ""

echo "=========================================="
echo "Test Results"
echo "=========================================="
echo -e "${GREEN}Passed:${NC} $PASSED_TESTS"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed:${NC} $FAILED_TESTS"
else
    echo -e "${GREEN}Failed:${NC} 0"
fi
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    exit 1
fi
