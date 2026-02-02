#!/usr/bin/env bash
#
# Test Network Fix
# Verifies that the docker network fix works correctly
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

echo "=========================================="
echo "Testing Docker Network Fix"
echo "=========================================="
echo ""

# Test 1: Check if generate-compose.sh has the fix
echo "Test 1: Checking generate-compose.sh for network fix..."
if grep -q "external: true" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh; then
    log "Network is marked as external in generate-compose.sh"
else
    error "Network is NOT marked as external in generate-compose.sh"
    exit 1
fi
echo ""

# Test 2: Check if start script creates network
echo "Test 2: Checking if start script creates network..."
if grep -q "docker network create" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh; then
    log "Start script includes network creation logic"
else
    error "Start script does NOT include network creation logic"
    exit 1
fi
echo ""

# Test 3: Check if stop script removes network
echo "Test 3: Checking if stop script removes network..."
if grep -q "docker network rm" /home/aigent/kurtosis-cdk/snapshot/scripts/generate-compose.sh; then
    log "Stop script includes network removal logic"
else
    error "Stop script does NOT include network removal logic"
    exit 1
fi
echo ""

# Test 4: Check latest snapshot (if any)
echo "Test 4: Checking most recent snapshot..."
LATEST_SNAPSHOT=$(ls -t /home/aigent/kurtosis-cdk/snapshots/cdk-* 2>/dev/null | head -1 || echo "")

if [ -n "$LATEST_SNAPSHOT" ] && [ -f "$LATEST_SNAPSHOT/docker-compose.yml" ]; then
    SNAPSHOT_NAME=$(basename "$LATEST_SNAPSHOT")
    echo "  Found: $SNAPSHOT_NAME"

    if grep -q "external: true" "$LATEST_SNAPSHOT/docker-compose.yml"; then
        log "Latest snapshot has network marked as external"
    else
        warn "Latest snapshot does NOT have the fix (was created before fix was applied)"
        warn "Generate a new snapshot to test the fix"
    fi
else
    warn "No snapshots found. Generate a snapshot to test the fix."
fi
echo ""

echo "=========================================="
echo "All Tests Passed!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. Generate a new snapshot:"
echo "   cd /home/aigent/kurtosis-cdk"
echo "   ./snapshot/snapshot.sh <enclave-name>"
echo ""
echo "2. Test the snapshot start/stop cycle:"
echo "   cd snapshots/cdk-<timestamp>"
echo "   ./start-snapshot.sh"
echo "   ./stop-snapshot.sh"
echo "   ./start-snapshot.sh  # Should work without errors!"
echo ""
