#!/usr/bin/env bash
#
# Assert op-node-001 healthcheck is working after docker compose up -d
# Run this from within a snapshot directory
#
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[ASSERT]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    error "docker-compose.yml not found in current directory"
    error "Please run this script from within a snapshot directory"
    exit 1
fi

# Check if op-node-001 service exists
if ! grep -q "op-node-001:" docker-compose.yml; then
    warn "No op-node-001 service found in docker-compose.yml"
    warn "This snapshot may not have L2 networks configured"
    exit 0
fi

log "Found op-node-001 service in docker-compose.yml"

# Get snapshot ID from directory name or docker-compose
SNAPSHOT_ID=$(basename "$(pwd)")
CONTAINER_NAME="$SNAPSHOT_ID-op-node-001"

# Check if container is running
if ! docker ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -q "$CONTAINER_NAME"; then
    error "Container $CONTAINER_NAME is not running"
    error "Please start the snapshot first with: docker compose up -d"
    exit 1
fi

log "Container $CONTAINER_NAME is running"

# Wait for healthcheck to complete (with timeout)
log "Waiting for op-node-001 healthcheck to complete..."

TIMEOUT=300  # 5 minutes
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Get health status
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "no_healthcheck")

    if [ "$HEALTH_STATUS" = "healthy" ]; then
        log "✓ op-node-001 is HEALTHY!"

        # Show healthcheck details
        log ""
        log "Healthcheck details:"
        docker inspect --format='{{json .State.Health}}' "$CONTAINER_NAME" | jq -r '.Log[-1] | "  Last check: \(.Start)\n  Exit code: \(.ExitCode)\n  Output: \(.Output)"' 2>/dev/null || docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' "$CONTAINER_NAME" | tail -5

        log ""
        log "=== ASSERTION PASSED ==="
        log "✓ op-node-001 healthcheck is working correctly"
        log "✓ aggkit services can now start (if configured)"
        exit 0

    elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
        error "✗ op-node-001 is UNHEALTHY!"
        error ""
        error "Healthcheck logs:"
        docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' "$CONTAINER_NAME" | tail -20
        error ""
        error "Container logs (last 50 lines):"
        docker logs --tail 50 "$CONTAINER_NAME"
        error ""
        error "=== ASSERTION FAILED ==="
        error "✗ op-node-001 healthcheck is not working"
        exit 1

    elif [ "$HEALTH_STATUS" = "no_healthcheck" ]; then
        error "✗ Container has no healthcheck defined!"
        error "This snapshot was generated with an old version of the scripts"
        error "Please regenerate the snapshot with the latest version"
        exit 1
    fi

    # Still starting or checking
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        log "Health status: $HEALTH_STATUS (elapsed: ${ELAPSED}s / ${TIMEOUT}s)"
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

# Timeout reached
error "✗ Timeout waiting for op-node-001 to become healthy after ${TIMEOUT}s"
error ""
error "Final health status: $HEALTH_STATUS"
error ""
error "Recent healthcheck logs:"
docker inspect --format='{{range .State.Health.Log}}{{.Output}}{{end}}' "$CONTAINER_NAME" | tail -20
error ""
error "Container logs (last 50 lines):"
docker logs --tail 50 "$CONTAINER_NAME"
error ""
error "=== ASSERTION FAILED ==="
error "✗ op-node-001 did not become healthy within timeout"
exit 1
