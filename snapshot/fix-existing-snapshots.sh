#!/usr/bin/env bash
#
# Fix Existing Snapshots - Network Configuration Update
# Updates existing snapshots to use external networks
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

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

# Check if running from correct directory
SNAPSHOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/snapshots"

if [ ! -d "$SNAPSHOTS_DIR" ]; then
    error "Snapshots directory not found: $SNAPSHOTS_DIR"
    exit 1
fi

log "Fixing existing snapshots in: $SNAPSHOTS_DIR"
log ""

FIXED_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0

# Process each snapshot directory
for snapshot_dir in "$SNAPSHOTS_DIR"/cdk-*; do
    if [ ! -d "$snapshot_dir" ]; then
        continue
    fi

    SNAPSHOT_ID=$(basename "$snapshot_dir")
    log "Processing: $SNAPSHOT_ID"

    # Check if docker-compose.yml exists
    if [ ! -f "$snapshot_dir/docker-compose.yml" ]; then
        warn "  No docker-compose.yml found, skipping"
        ((SKIPPED_COUNT++))
        continue
    fi

    # Extract network name from docker-compose.yml
    NETWORK_NAME=$(grep -A 2 "^networks:" "$snapshot_dir/docker-compose.yml" | grep "name:" | awk '{print $2}' || echo "")

    if [ -z "$NETWORK_NAME" ]; then
        warn "  Could not extract network name, skipping"
        ((SKIPPED_COUNT++))
        continue
    fi

    log "  Network name: $NETWORK_NAME"

    # Check if already using external network
    if grep -q "external: true" "$snapshot_dir/docker-compose.yml"; then
        log "  Already fixed, skipping"
        ((SKIPPED_COUNT++))
        continue
    fi

    # Fix docker-compose.yml - update network configuration
    log "  Updating docker-compose.yml..."
    if sed -i '/^networks:/,/^$/c\
networks:\
  l1-network:\
    name: '"$NETWORK_NAME"'\
    external: true\
\
# No volumes - all state is baked into images\
# L1 state is baked in, L2 starts fresh with config-only mounts\
# Agglayer and AggKit use host-mounted config files (read-only)' "$snapshot_dir/docker-compose.yml"; then
        log "  ✓ docker-compose.yml updated"
    else
        error "  Failed to update docker-compose.yml"
        ((ERROR_COUNT++))
        continue
    fi

    # Fix start-snapshot.sh
    log "  Updating start-snapshot.sh..."
    cat > "$snapshot_dir/start-snapshot.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

NETWORK_NAME="$NETWORK_NAME"

echo "Starting Ethereum L1 snapshot..."

# Create network if it doesn't exist
if ! docker network inspect "\$NETWORK_NAME" &> /dev/null; then
    echo "Creating Docker network: \$NETWORK_NAME"
    docker network create "\$NETWORK_NAME" --driver bridge
else
    echo "Docker network already exists: \$NETWORK_NAME"
fi

docker-compose -f docker-compose.yml up -d

echo ""
echo "Waiting for services to be healthy..."
sleep 5

echo ""
echo "Service status:"
docker-compose -f docker-compose.yml ps

echo ""
echo "To view logs:"
echo "  docker-compose -f docker-compose.yml logs -f"
echo ""
echo "To check block number:"
echo "  curl -s http://localhost:8545 -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | xargs printf '%d\n'"
EOF

    chmod +x "$snapshot_dir/start-snapshot.sh"
    log "  ✓ start-snapshot.sh updated"

    # Fix stop-snapshot.sh
    log "  Updating stop-snapshot.sh..."
    cat > "$snapshot_dir/stop-snapshot.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

NETWORK_NAME="$NETWORK_NAME"

echo "Stopping Ethereum L1 snapshot..."
docker-compose -f docker-compose.yml down

# Remove the network if it exists and is not in use
if docker network inspect "\$NETWORK_NAME" &> /dev/null; then
    echo "Removing Docker network: \$NETWORK_NAME"
    docker network rm "\$NETWORK_NAME" 2>/dev/null || echo "Network still in use or already removed"
fi

echo "Snapshot stopped."
EOF

    chmod +x "$snapshot_dir/stop-snapshot.sh"
    log "  ✓ stop-snapshot.sh updated"

    log "  ✅ Successfully fixed $SNAPSHOT_ID"
    ((FIXED_COUNT++))
    echo ""
done

log ""
log "=========================================="
log "Summary:"
log "  Fixed: $FIXED_COUNT"
log "  Skipped: $SKIPPED_COUNT"
log "  Errors: $ERROR_COUNT"
log "=========================================="

if [ $ERROR_COUNT -gt 0 ]; then
    error "Some snapshots could not be fixed. Please check the errors above."
    exit 1
fi

log "All snapshots have been processed successfully!"
log ""
log "You can now restart any snapshot with:"
log "  cd $SNAPSHOTS_DIR/<snapshot-name>"
log "  ./start-snapshot.sh"

exit 0
