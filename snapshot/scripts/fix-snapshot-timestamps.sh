#!/usr/bin/env bash
#
# Fix Snapshot Timestamps
# Updates existing snapshots to use libfaketime to freeze time at snapshot creation
# This prevents L1 block production from stopping due to beacon chain time drift
#
# Usage: fix-snapshot-timestamps.sh <SNAPSHOT_DIR>
#

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <SNAPSHOT_DIR>" >&2
    echo "Example: $0 snapshots/cdk-20260205-144517" >&2
    exit 1
fi

SNAPSHOT_DIR="$1"

if [ ! -d "$SNAPSHOT_DIR" ]; then
    echo "ERROR: Snapshot directory not found: $SNAPSHOT_DIR" >&2
    exit 1
fi

if [ ! -f "$SNAPSHOT_DIR/docker-compose.yml" ]; then
    echo "ERROR: docker-compose.yml not found in $SNAPSHOT_DIR" >&2
    exit 1
fi

echo "==================================================================="
echo " Fixing Snapshot Timestamp Issue"
echo "==================================================================="
echo
echo "This script fixes the L1 block production issue caused by time drift."
echo "It modifies the snapshot to use libfaketime to freeze container time"
echo "at the snapshot creation moment."
echo
echo "Snapshot: $SNAPSHOT_DIR"
echo

# Step 1: Extract the original MIN_GENESIS_TIME from the beacon container
echo "[1/4] Extracting snapshot creation timestamp..."

BEACON_IMAGE=$(grep -A2 "beacon:" "$SNAPSHOT_DIR/docker-compose.yml" | grep "image:" | awk '{print $2}')
if [ -z "$BEACON_IMAGE" ]; then
    echo "ERROR: Could not find beacon image in docker-compose.yml" >&2
    exit 1
fi

echo "  Beacon image: $BEACON_IMAGE"

# Create temp container to extract config
TEMP_CONTAINER="temp-beacon-extract-$$"
docker create --name "$TEMP_CONTAINER" "$BEACON_IMAGE" >/dev/null 2>&1
docker cp "$TEMP_CONTAINER:/network-configs/config.yaml" /tmp/beacon-config-$$.yaml >/dev/null 2>&1
docker rm "$TEMP_CONTAINER" >/dev/null 2>&1

SNAPSHOT_TIME=$(grep "^MIN_GENESIS_TIME:" /tmp/beacon-config-$$.yaml | awk '{print $2}')
rm -f /tmp/beacon-config-$$.yaml

if [ -z "$SNAPSHOT_TIME" ]; then
    echo "ERROR: Could not extract MIN_GENESIS_TIME from beacon config" >&2
    exit 1
fi

echo "  Snapshot genesis time: $SNAPSHOT_TIME"
echo "  Snapshot created at: $(date -d @$SNAPSHOT_TIME '+%Y-%m-%d %H:%M:%S UTC')"

CURRENT_TIME=$(date +%s)
TIME_DRIFT=$((CURRENT_TIME - SNAPSHOT_TIME))

echo "  Current time: $CURRENT_TIME ($(date -d @$CURRENT_TIME '+%Y-%m-%d %H:%M:%S UTC'))"
echo "  Time drift: $TIME_DRIFT seconds ($((TIME_DRIFT / 3600)) hours)"
echo

# Step 2: Create faketime wrapper for geth
echo "[2/4] Creating faketime wrapper for geth..."

mkdir -p "$SNAPSHOT_DIR/scripts"

cat > "$SNAPSHOT_DIR/scripts/geth-faketime-entrypoint.sh" << 'FAKETIME_EOF'
#!/bin/sh
set -e

# Install libfaketime if not present
if [ ! -f /usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 ]; then
    echo "Installing libfaketime..."
    apt-get update -qq && apt-get install -y -qq faketime > /dev/null 2>&1
fi

# Set fake time to snapshot creation time
export FAKETIME="__SNAPSHOT_TIME__"
export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1"

echo "==================================="
echo "Geth Faketime Wrapper"
echo "==================================="
echo "Freezing time at: $(date -d @__SNAPSHOT_TIME__ '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date)"
echo "==================================="
echo

exec "$@"
FAKETIME_EOF

sed -i "s/__SNAPSHOT_TIME__/@$SNAPSHOT_TIME/" "$SNAPSHOT_DIR/scripts/geth-faketime-entrypoint.sh"
chmod +x "$SNAPSHOT_DIR/scripts/geth-faketime-entrypoint.sh"

echo "  Created: $SNAPSHOT_DIR/scripts/geth-faketime-entrypoint.sh"

# Step 3: Create faketime wrapper for beacon
echo "[3/4] Creating faketime wrapper for beacon and validator..."

cat > "$SNAPSHOT_DIR/scripts/beacon-faketime-entrypoint.sh" << 'FAKETIME_EOF'
#!/bin/sh
set -e

# Install libfaketime if not present
if [ ! -f /usr/local/lib/faketime/libfaketime.so.1 ]; then
    echo "Installing libfaketime..."
    apk add --no-cache libfaketime > /dev/null 2>&1
fi

# Set fake time to snapshot creation time
export FAKETIME="__SNAPSHOT_TIME__"
export LD_PRELOAD="/usr/local/lib/faketime/libfaketime.so.1"

echo "==================================="
echo "Beacon Faketime Wrapper"
echo "==================================="
echo "Freezing time at: $FAKETIME"
echo "==================================="
echo

exec "$@"
FAKETIME_EOF

sed -i "s/__SNAPSHOT_TIME__/@$SNAPSHOT_TIME/" "$SNAPSHOT_DIR/scripts/beacon-faketime-entrypoint.sh"
chmod +x "$SNAPSHOT_DIR/scripts/beacon-faketime-entrypoint.sh"

echo "  Created: $SNAPSHOT_DIR/scripts/beacon-faketime-entrypoint.sh"
echo

# Step 4: Update docker-compose.yml
echo "[4/4] Updating docker-compose.yml..."

# Backup original
BACKUP_FILE="$SNAPSHOT_DIR/docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SNAPSHOT_DIR/docker-compose.yml" "$BACKUP_FILE"
echo "  Backup saved: $BACKUP_FILE"

# Use Python to properly modify YAML
python3 << PYTHON_EOF
import sys
import re

compose_file = "$SNAPSHOT_DIR/docker-compose.yml"

with open(compose_file, 'r') as f:
    content = f.read()

# Function to add entrypoint and volumes to a service
def add_faketime_to_service(service_name, script_name):
    global content

    # Find the service section
    service_pattern = rf'(  {service_name}:\n.*?    hostname: {service_name}\n)'

    # Check if entrypoint already exists
    if f'entrypoint.*{script_name}' in content:
        print(f"  Skipping {service_name} - already has faketime entrypoint")
        return

    # Add entrypoint after hostname
    content = re.sub(
        service_pattern,
        rf'\1    entrypoint: ["/scripts/{script_name}"]\n',
        content,
        flags=re.DOTALL
    )

    # Add volumes section if not present
    # Find where to insert (after ports, before depends_on or restart)
    volume_insert_pattern = rf'(  {service_name}:.*?)(    (?:depends_on|restart):)'

    if not re.search(rf'{service_name}:.*?volumes:', content, re.DOTALL):
        content = re.sub(
            volume_insert_pattern,
            r'\1    volumes:\n      - ./scripts:/scripts:ro\n\1',
            content,
            flags=re.DOTALL
        )

# Add faketime to geth
add_faketime_to_service('geth', 'geth-faketime-entrypoint.sh')

# Add faketime to beacon
add_faketime_to_service('beacon', 'beacon-faketime-entrypoint.sh')

# Add faketime to validator
add_faketime_to_service('validator', 'beacon-faketime-entrypoint.sh')

with open(compose_file, 'w') as f:
    f.write(content)

print("  ✓ Updated docker-compose.yml")

PYTHON_EOF

echo

echo "==================================================================="
echo " ✓ Snapshot timestamp fix complete!"
echo "==================================================================="
echo
echo "The L1 containers (geth, beacon, validator) will now use faketime to"
echo "freeze their system time at the snapshot creation moment. This allows"
echo "the beacon chain to continue producing blocks correctly regardless of"
echo "how much time has elapsed since the snapshot was created."
echo
echo "To apply the fix:"
echo "  cd $SNAPSHOT_DIR"
echo "  docker-compose down"
echo "  docker-compose up -d"
echo
echo "Note: The first startup will be slightly slower as containers install"
echo "libfaketime. Subsequent restarts will be normal speed."
echo

exit 0
