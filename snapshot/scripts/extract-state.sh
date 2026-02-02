#!/usr/bin/env bash
#
# State Extraction Script
# Stops L1 containers and extracts their datadirs
#
# Usage: extract-state.sh <DISCOVERY_JSON> <OUTPUT_DIR>
#

set -euo pipefail

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <DISCOVERY_JSON> <OUTPUT_DIR>" >&2
    exit 1
fi

DISCOVERY_JSON="$1"
OUTPUT_DIR="$2"

# Check dependencies
for cmd in docker jq tar; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Required command '$cmd' not found" >&2
        exit 1
    fi
done

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting state extraction"

# Read container info from discovery JSON
if [ ! -f "$DISCOVERY_JSON" ]; then
    log "ERROR: Discovery file not found: $DISCOVERY_JSON"
    exit 1
fi

GETH_CONTAINER=$(jq -r '.geth.container_name' "$DISCOVERY_JSON")
BEACON_CONTAINER=$(jq -r '.beacon.container_name' "$DISCOVERY_JSON")
VALIDATOR_CONTAINER=$(jq -r '.validator.container_name' "$DISCOVERY_JSON")

# Check if agglayer was discovered
AGGLAYER_FOUND=$(jq -r '.agglayer.found' "$DISCOVERY_JSON")
if [ "$AGGLAYER_FOUND" = "true" ]; then
    AGGLAYER_CONTAINER=$(jq -r '.agglayer.container_name' "$DISCOVERY_JSON")
fi

log "Containers to process:"
log "  Geth: $GETH_CONTAINER"
log "  Beacon: $BEACON_CONTAINER"
log "  Validator: $VALIDATOR_CONTAINER"
if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "  Agglayer: $AGGLAYER_CONTAINER"
fi

# Create output directories
mkdir -p "$OUTPUT_DIR/datadirs"
mkdir -p "$OUTPUT_DIR/artifacts"
mkdir -p "$OUTPUT_DIR/metadata"
mkdir -p "$OUTPUT_DIR/config/agglayer"

# ============================================================================
# STEP 1: Stop containers gracefully
# ============================================================================

log "Stopping containers gracefully..."

for container in "$GETH_CONTAINER" "$BEACON_CONTAINER" "$VALIDATOR_CONTAINER"; do
    if docker ps -q --filter "name=$container" | grep -q .; then
        log "  Stopping $container..."
        docker stop "$container" --time 30

        # Wait for container to fully stop
        timeout=30
        while [ $timeout -gt 0 ]; do
            state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "gone")
            if [ "$state" = "exited" ]; then
                log "  $container stopped successfully"
                break
            fi
            sleep 1
            timeout=$((timeout - 1))
        done

        if [ $timeout -eq 0 ]; then
            log "WARNING: Container $container did not stop within timeout"
        fi
    else
        log "  Container $container already stopped"
    fi
done

log "All containers stopped"

# ============================================================================
# STEP 2: Validate containers are stopped
# ============================================================================

log "Validating container states..."

for container in "$GETH_CONTAINER" "$BEACON_CONTAINER" "$VALIDATOR_CONTAINER"; do
    state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "gone")
    if [ "$state" != "exited" ]; then
        log "ERROR: Container $container is not stopped (state: $state)"
        log "Cannot proceed with extraction"
        exit 1
    fi
done

log "All containers confirmed stopped"

# ============================================================================
# STEP 3: Extract Geth datadir
# ============================================================================

log "Extracting Geth execution datadir..."

GETH_DATADIR="/data/geth/execution-data"
GETH_TAR="$OUTPUT_DIR/datadirs/geth.tar"

log "  Source: $GETH_DATADIR"
log "  Target: $GETH_TAR"

# Create tarball from stopped container
docker export "$GETH_CONTAINER" | tar -x --to-stdout "$GETH_DATADIR" > /dev/null 2>&1 || true

# Better approach: use docker cp
docker cp "$GETH_CONTAINER:$GETH_DATADIR" "$OUTPUT_DIR/datadirs/geth-data"

# Create tarball
tar -czf "$GETH_TAR" -C "$OUTPUT_DIR/datadirs" geth-data
rm -rf "$OUTPUT_DIR/datadirs/geth-data"

if [ -f "$GETH_TAR" ]; then
    size=$(du -h "$GETH_TAR" | cut -f1)
    log "  Geth datadir extracted: $size"
else
    log "ERROR: Failed to extract Geth datadir"
    exit 1
fi

# ============================================================================
# STEP 4: Extract Lighthouse Beacon datadir
# ============================================================================

log "Extracting Lighthouse beacon datadir..."

BEACON_DATADIR="/data/lighthouse/beacon-data"
BEACON_TAR="$OUTPUT_DIR/datadirs/lighthouse_beacon.tar"

log "  Source: $BEACON_DATADIR"
log "  Target: $BEACON_TAR"

docker cp "$BEACON_CONTAINER:$BEACON_DATADIR" "$OUTPUT_DIR/datadirs/beacon-data"

# Create tarball
tar -czf "$BEACON_TAR" -C "$OUTPUT_DIR/datadirs" beacon-data
rm -rf "$OUTPUT_DIR/datadirs/beacon-data"

if [ -f "$BEACON_TAR" ]; then
    size=$(du -h "$BEACON_TAR" | cut -f1)
    log "  Beacon datadir extracted: $size"
else
    log "ERROR: Failed to extract Beacon datadir"
    exit 1
fi

# ============================================================================
# STEP 5: Extract Lighthouse Validator datadir
# ============================================================================

log "Extracting Lighthouse validator datadir..."

VALIDATOR_TAR="$OUTPUT_DIR/datadirs/lighthouse_validator.tar"
mkdir -p "$OUTPUT_DIR/datadirs/validator-data"

# Extract from both locations
log "  Extracting validator keys..."
docker cp "$VALIDATOR_CONTAINER:/root/.lighthouse/custom" "$OUTPUT_DIR/datadirs/validator-data/lighthouse" 2>/dev/null || true

log "  Extracting validator keystore..."
docker cp "$VALIDATOR_CONTAINER:/validator-keys" "$OUTPUT_DIR/datadirs/validator-data/validator-keys" 2>/dev/null || true

# Verify critical directories and files exist
if [ ! -d "$OUTPUT_DIR/datadirs/validator-data/validator-keys/keys" ]; then
    log "ERROR: Validator keys directory not found"
    exit 1
fi

# Note: The secrets directory may be empty due to restrictive permissions (700)
# We fall back to lodestar-secrets which contains the same password files
if [ ! -d "$OUTPUT_DIR/datadirs/validator-data/validator-keys/lodestar-secrets" ]; then
    log "ERROR: Validator lodestar-secrets directory not found"
    exit 1
fi

if [ ! -f "$OUTPUT_DIR/datadirs/validator-data/validator-keys/keys/slashing_protection.sqlite" ]; then
    log "ERROR: Critical file missing: slashing_protection.sqlite"
    log "Cannot proceed without slashing protection database"
    exit 1
fi

# Count validators
VALIDATOR_COUNT=$(ls -1 "$OUTPUT_DIR/datadirs/validator-data/validator-keys/keys" | grep "^0x" | wc -l)
log "  Found $VALIDATOR_COUNT validators with slashing protection"

# Create tarball
tar -czf "$VALIDATOR_TAR" -C "$OUTPUT_DIR/datadirs" validator-data
rm -rf "$OUTPUT_DIR/datadirs/validator-data"

if [ -f "$VALIDATOR_TAR" ]; then
    size=$(du -h "$VALIDATOR_TAR" | cut -f1)
    log "  Validator datadir extracted: $size"
    log "  Contains: $VALIDATOR_COUNT validators with secrets"
else
    log "ERROR: Failed to extract Validator datadir"
    exit 1
fi

# ============================================================================
# STEP 6: Extract Agglayer configuration (optional)
# ============================================================================

if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "Extracting Agglayer configuration files..."

    # Extract config.toml
    log "  Extracting config.toml..."
    if docker cp "$AGGLAYER_CONTAINER:/etc/agglayer/config.toml" "$OUTPUT_DIR/config/agglayer/config.toml" 2>/dev/null; then
        log "  ✓ config.toml extracted"
    else
        log "  WARNING: config.toml not found"
    fi

    # Extract aggregator keystore
    log "  Extracting aggregator.keystore..."
    if docker cp "$AGGLAYER_CONTAINER:/etc/agglayer/aggregator.keystore" "$OUTPUT_DIR/config/agglayer/aggregator.keystore" 2>/dev/null; then
        log "  ✓ aggregator.keystore extracted"
    else
        log "  WARNING: aggregator.keystore not found"
    fi

    # Verify critical files exist
    if [ ! -f "$OUTPUT_DIR/config/agglayer/config.toml" ]; then
        log "WARNING: Agglayer config.toml not found"
    fi

    if [ ! -f "$OUTPUT_DIR/config/agglayer/aggregator.keystore" ]; then
        log "WARNING: Agglayer aggregator.keystore not found"
    fi

    log "Agglayer configuration extracted"
    log "  Note: Storage and backups directories NOT extracted (stateless by design)"

    # Adapt the config for docker-compose environment
    log "Adapting agglayer config for docker-compose..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -x "$SCRIPT_DIR/adapt-agglayer-config.sh" ]; then
        "$SCRIPT_DIR/adapt-agglayer-config.sh" "$OUTPUT_DIR/config/agglayer"
        log "  ✓ Agglayer config adapted"
    else
        log "  WARNING: adapt-agglayer-config.sh not found or not executable"
    fi
else
    log "Skipping Agglayer extraction (not found in enclave)"
fi

# ============================================================================
# STEP 7: Extract configuration artifacts
# ============================================================================

log "Extracting configuration artifacts..."

# Extract genesis and network configs from Geth
log "  Extracting genesis.json..."
docker cp "$GETH_CONTAINER:/network-configs/genesis.json" "$OUTPUT_DIR/artifacts/genesis.json" 2>/dev/null || log "  genesis.json not found in expected location"

# Extract JWT secret
log "  Extracting JWT secret..."
docker cp "$GETH_CONTAINER:/jwt/jwtsecret" "$OUTPUT_DIR/artifacts/jwt.hex" 2>/dev/null || log "  JWT secret not found"

# Extract beacon chain spec if available
log "  Extracting beacon chain spec..."
docker cp "$BEACON_CONTAINER:/network-configs/config.yaml" "$OUTPUT_DIR/artifacts/chain-spec.yaml" 2>/dev/null || log "  chain-spec.yaml not found"

# Extract validator definitions if available
log "  Extracting validator definitions..."
docker cp "$VALIDATOR_CONTAINER:/validator-keys/keys" "$OUTPUT_DIR/artifacts/validator-keys" 2>/dev/null || log "  validator keys not found"

# Create bootnodes file (will be populated later if needed)
touch "$OUTPUT_DIR/artifacts/bootnodes.txt"

log "Configuration artifacts extracted"

# ============================================================================
# Summary
# ============================================================================

log "State extraction complete!"
log "Extracted files:"
ls -lh "$OUTPUT_DIR/datadirs/"*.tar | awk '{print "  " $9 " (" $5 ")"}'

log "Artifacts:"
find "$OUTPUT_DIR/artifacts" -type f | sed 's/^/  /'

if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "Agglayer config:"
    find "$OUTPUT_DIR/config/agglayer" -type f | sed 's/^/  /'
fi

exit 0
