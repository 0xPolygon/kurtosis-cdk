#!/usr/bin/env bash
#
# Test script to verify op-node healthcheck is working correctly
# This script creates a new snapshot and validates the op-node-001 healthcheck
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check if enclave name is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <enclave-name> [snapshot-dir]"
    echo ""
    echo "Arguments:"
    echo "  enclave-name  : Name of the Kurtosis enclave to snapshot"
    echo "  snapshot-dir  : (Optional) Path to existing snapshot directory to test"
    echo ""
    echo "Examples:"
    echo "  $0 my-enclave                    # Create new snapshot and test"
    echo "  $0 my-enclave ./snapshots/cdk-*  # Test existing snapshot"
    exit 1
fi

ENCLAVE_NAME="$1"
SNAPSHOT_DIR="${2:-}"

# If snapshot directory not provided, create a new snapshot
if [ -z "$SNAPSHOT_DIR" ]; then
    log "Creating new snapshot for enclave: $ENCLAVE_NAME"

    # Run the snapshot script
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ! "$SCRIPT_DIR/snapshot.sh" "$ENCLAVE_NAME"; then
        error "Failed to create snapshot"
        exit 1
    fi

    # Find the most recent snapshot directory
    SNAPSHOT_DIR=$(find "$SCRIPT_DIR/../snapshots" -maxdepth 1 -type d -name "cdk-*" | sort | tail -1)

    if [ -z "$SNAPSHOT_DIR" ] || [ ! -d "$SNAPSHOT_DIR" ]; then
        error "Could not find created snapshot directory"
        exit 1
    fi

    log "Using newly created snapshot: $SNAPSHOT_DIR"
else
    log "Using existing snapshot: $SNAPSHOT_DIR"
fi

# Navigate to snapshot directory
cd "$SNAPSHOT_DIR"

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    error "docker-compose.yml not found in $SNAPSHOT_DIR"
    exit 1
fi

# Check if op-node-001 service exists in docker-compose.yml
if ! grep -q "op-node-001:" docker-compose.yml; then
    warn "No op-node-001 service found in docker-compose.yml"
    warn "This snapshot may not have L2 networks configured"
    exit 0
fi

log "Found op-node-001 service in docker-compose.yml"

# Extract and validate healthcheck configuration
log "Validating healthcheck configuration..."

# Check if healthcheck is defined for op-node-001
if ! sed -n '/op-node-001:/,/^  [a-z]/p' docker-compose.yml | grep -q "healthcheck:"; then
    error "No healthcheck defined for op-node-001 service"
    exit 1
fi

# Extract healthcheck test command
HEALTHCHECK_CMD=$(sed -n '/op-node-001:/,/^  [a-z]/p' docker-compose.yml | grep -A 1 "test:" | tail -1 | sed 's/^[[:space:]]*//')

log "Healthcheck command: $HEALTHCHECK_CMD"

# Validate healthcheck uses curl (not wget)
if echo "$HEALTHCHECK_CMD" | grep -q "wget"; then
    error "Healthcheck uses 'wget' which may not be available in op-node container"
    exit 1
elif echo "$HEALTHCHECK_CMD" | grep -q "curl"; then
    log "✓ Healthcheck uses 'curl' (good)"
else
    warn "Healthcheck doesn't use curl or wget - using custom check"
fi

# Validate healthcheck makes a proper RPC call
if echo "$HEALTHCHECK_CMD" | grep -q "optimism_syncStatus\|metrics"; then
    log "✓ Healthcheck makes a proper health endpoint call"
else
    warn "Healthcheck may not be using optimal health endpoint"
fi

# Start the snapshot
log "Starting snapshot containers..."

# Ensure network exists
NETWORK_NAME=$(grep "name:" docker-compose.yml | grep "snapshot-" | awk '{print $2}')
if [ -n "$NETWORK_NAME" ]; then
    if ! docker network inspect "$NETWORK_NAME" &> /dev/null; then
        log "Creating Docker network: $NETWORK_NAME"
        docker network create "$NETWORK_NAME" --driver bridge
    fi
fi

# Start services
if ! docker compose up -d; then
    error "Failed to start docker compose services"
    exit 1
fi

log "Services started. Waiting for op-node-001 to become healthy..."

# Wait for op-node-001 to be healthy (with timeout)
TIMEOUT=300  # 5 minutes
ELAPSED=0
INTERVAL=5

CONTAINER_NAME=$(docker compose ps -q op-node-001 2>/dev/null || echo "")
if [ -z "$CONTAINER_NAME" ]; then
    # Try to find by container name pattern
    SNAPSHOT_ID=$(basename "$SNAPSHOT_DIR")
    CONTAINER_NAME="$SNAPSHOT_ID-op-node-001"
fi

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check container health status
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "no_healthcheck")

    if [ "$HEALTH_STATUS" = "healthy" ]; then
        log "✓ op-node-001 is healthy!"
        break
    elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
        error "op-node-001 is unhealthy!"
        log "Showing recent healthcheck logs:"
        docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' "$CONTAINER_NAME" | tail -20
        log ""
        log "Showing container logs:"
        docker logs --tail 50 "$CONTAINER_NAME"
        exit 1
    elif [ "$HEALTH_STATUS" = "no_healthcheck" ]; then
        error "Container has no healthcheck defined!"
        exit 1
    fi

    log "Health status: $HEALTH_STATUS (elapsed: ${ELAPSED}s / ${TIMEOUT}s)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    error "Timeout waiting for op-node-001 to become healthy"
    log "Showing recent healthcheck logs:"
    docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' "$CONTAINER_NAME" | tail -20
    log ""
    log "Showing container logs:"
    docker logs --tail 50 "$CONTAINER_NAME"
    exit 1
fi

# Verify healthcheck is actually working by running it manually
log "Verifying healthcheck command works manually..."

if ! docker exec "$CONTAINER_NAME" sh -c "$(echo "$HEALTHCHECK_CMD" | sed 's/\["CMD",\s*//;s/\]$//;s/",\s*"/ /g;s/"//g')"; then
    error "Manual healthcheck execution failed!"
    exit 1
fi

log "✓ Manual healthcheck execution successful"

# Show final status
log ""
log "=== FINAL STATUS ==="
docker compose ps

log ""
log "=== HEALTHCHECK VERIFICATION PASSED ==="
log "✓ op-node-001 healthcheck is properly configured"
log "✓ op-node-001 container is healthy"
log "✓ Healthcheck command executes successfully"

# Cleanup prompt
log ""
read -p "Clean up and stop containers? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Stopping containers..."
    docker compose down

    if [ -n "$NETWORK_NAME" ]; then
        log "Removing network: $NETWORK_NAME"
        docker network rm "$NETWORK_NAME" 2>/dev/null || true
    fi

    log "Cleanup complete"
fi

exit 0
