#!/usr/bin/env bash
#
# Metadata Generation Script
# Captures L1 state metadata and generates checksums
#
# Usage: generate-metadata.sh <DISCOVERY_JSON> <OUTPUT_DIR>
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
for cmd in docker jq curl sha256sum; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Required command '$cmd' not found" >&2
        exit 1
    fi
done

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting metadata generation"

# Read container info from discovery JSON
if [ ! -f "$DISCOVERY_JSON" ]; then
    log "ERROR: Discovery file not found: $DISCOVERY_JSON"
    exit 1
fi

ENCLAVE_NAME=$(jq -r '.enclave_name' "$DISCOVERY_JSON")
ENCLAVE_UUID=$(jq -r '.enclave_uuid' "$DISCOVERY_JSON")
GETH_CONTAINER=$(jq -r '.geth.container_name' "$DISCOVERY_JSON")
GETH_IMAGE=$(jq -r '.geth.image' "$DISCOVERY_JSON")
BEACON_CONTAINER=$(jq -r '.beacon.container_name' "$DISCOVERY_JSON")
BEACON_IMAGE=$(jq -r '.beacon.image' "$DISCOVERY_JSON")
VALIDATOR_CONTAINER=$(jq -r '.validator.container_name' "$DISCOVERY_JSON")
VALIDATOR_IMAGE=$(jq -r '.validator.image' "$DISCOVERY_JSON")

# Create metadata directory
mkdir -p "$OUTPUT_DIR/metadata"

# ============================================================================
# STEP 1: Query block state (before stopping)
# ============================================================================

log "Querying current L1 block state..."

# Try to get block number and hash from running container
BLOCK_NUMBER=""
BLOCK_HASH=""
GENESIS_HASH=""

# First, check if pre-stop-state.json exists and use it (preferred method)
PRE_STOP_STATE="$OUTPUT_DIR/pre-stop-state.json"
if [ -f "$PRE_STOP_STATE" ]; then
    log "  Using pre-stop state from: $PRE_STOP_STATE"
    BLOCK_NUMBER=$(jq -r '.block_number' "$PRE_STOP_STATE" 2>/dev/null || echo "")
    BLOCK_HASH=$(jq -r '.block_hash' "$PRE_STOP_STATE" 2>/dev/null || echo "")
    BLOCK_TIMESTAMP=$(jq -r '.block_timestamp // empty' "$PRE_STOP_STATE" 2>/dev/null || echo "")
    GENESIS_HASH=$(jq -r '.genesis_hash' "$PRE_STOP_STATE" 2>/dev/null || echo "")

    if [ -n "$BLOCK_NUMBER" ] && [ "$BLOCK_NUMBER" != "null" ] && [ "$BLOCK_NUMBER" != "unknown" ]; then
        log "  Block number: $BLOCK_NUMBER"
    fi
    if [ -n "$BLOCK_HASH" ] && [ "$BLOCK_HASH" != "null" ] && [ "$BLOCK_HASH" != "unknown" ]; then
        log "  Block hash: $BLOCK_HASH"
    fi
    if [ -n "$BLOCK_TIMESTAMP" ] && [ "$BLOCK_TIMESTAMP" != "null" ] && [ "$BLOCK_TIMESTAMP" != "unknown" ]; then
        log "  Block timestamp: $BLOCK_TIMESTAMP"
    fi
    if [ -n "$GENESIS_HASH" ] && [ "$GENESIS_HASH" != "null" ] && [ "$GENESIS_HASH" != "unknown" ]; then
        log "  Genesis hash: $GENESIS_HASH"
    fi
fi

# Fallback to querying running container if pre-stop state is incomplete
if [ -z "$BLOCK_NUMBER" ] || [ "$BLOCK_NUMBER" = "unknown" ] || [ -z "$BLOCK_HASH" ] || [ "$BLOCK_HASH" = "unknown" ]; then
    log "  Pre-stop state incomplete, querying running container..."
    # Check if container is still running
    if docker ps -q --filter "name=$GETH_CONTAINER" | grep -q .; then
        log "  Container is running, querying block state..."

        # Get the RPC port from the container
        RPC_PORT=$(docker port "$GETH_CONTAINER" 8545 2>/dev/null | cut -d: -f2 || echo "")

        if [ -n "$RPC_PORT" ]; then
            log "  Found RPC endpoint at localhost:$RPC_PORT"

            # Query latest block using eth_getBlockByNumber (gets hash and number atomically)
            BLOCK_DATA=$(curl -s "http://localhost:$RPC_PORT" \
                -X POST \
                -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
                2>/dev/null || echo "")

            if [ -n "$BLOCK_DATA" ] && echo "$BLOCK_DATA" | jq -e '.result' &>/dev/null; then
                # Extract block number (convert hex to decimal)
                BLOCK_HEX=$(echo "$BLOCK_DATA" | jq -r '.result.number' 2>/dev/null || echo "")
                if [ -n "$BLOCK_HEX" ] && [ "$BLOCK_HEX" != "null" ]; then
                    BLOCK_NUMBER=$((16#${BLOCK_HEX#0x}))
                    log "  Current block number: $BLOCK_NUMBER"
                fi

                # Extract block hash
                BLOCK_HASH=$(echo "$BLOCK_DATA" | jq -r '.result.hash' 2>/dev/null || echo "")
                log "  Current block hash: $BLOCK_HASH"

                # Extract block timestamp (convert hex to decimal)
                BLOCK_TIMESTAMP_HEX=$(echo "$BLOCK_DATA" | jq -r '.result.timestamp' 2>/dev/null || echo "")
                if [ -n "$BLOCK_TIMESTAMP_HEX" ] && [ "$BLOCK_TIMESTAMP_HEX" != "null" ]; then
                    BLOCK_TIMESTAMP=$((16#${BLOCK_TIMESTAMP_HEX#0x}))
                    log "  Current block timestamp: $BLOCK_TIMESTAMP"
                fi
            fi

            # Get genesis hash
            GENESIS_DATA=$(curl -s "http://localhost:$RPC_PORT" \
                -X POST \
                -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' \
                2>/dev/null || echo "")

            if [ -n "$GENESIS_DATA" ] && echo "$GENESIS_DATA" | jq -e '.result' &>/dev/null; then
                GENESIS_HASH=$(echo "$GENESIS_DATA" | jq -r '.result.hash' 2>/dev/null || echo "")
                log "  Genesis hash: $GENESIS_HASH"
            fi
        fi

        # Fallback to docker exec if RPC query failed
        if [ -z "$BLOCK_NUMBER" ] || [ -z "$BLOCK_HASH" ]; then
            log "  RPC query failed, falling back to docker exec..."

            # Query via geth attach
            BLOCK_INFO=$(docker exec "$GETH_CONTAINER" sh -c 'geth attach --exec "eth.blockNumber" /data/geth/execution-data/geth.ipc 2>/dev/null' || echo "")

            if [ -n "$BLOCK_INFO" ]; then
                BLOCK_NUMBER="$BLOCK_INFO"
                log "  Current block number: $BLOCK_NUMBER"

                # Get block hash
                BLOCK_HASH=$(docker exec "$GETH_CONTAINER" sh -c "geth attach --exec \"eth.getBlock($BLOCK_NUMBER).hash\" /data/geth/execution-data/geth.ipc 2>/dev/null" || echo "")
                log "  Current block hash: $BLOCK_HASH"

                # Get genesis hash
                GENESIS_HASH=$(docker exec "$GETH_CONTAINER" sh -c 'geth attach --exec "eth.getBlock(0).hash" /data/geth/execution-data/geth.ipc 2>/dev/null' || echo "")
                log "  Genesis hash: $GENESIS_HASH"
            fi
        fi
    else
        log "  Container stopped, skipping live query"
    fi
fi

# If we couldn't get block info, set defaults
if [ -z "$BLOCK_NUMBER" ]; then
    log "  WARNING: Could not query block state"
    BLOCK_NUMBER="unknown"
    BLOCK_HASH="unknown"
    GENESIS_HASH="unknown"
fi

# ============================================================================
# STEP 2: Generate SHA256 manifest for tarballs
# ============================================================================

log "Generating SHA256 checksums for datadirs..."

MANIFEST_FILE="$OUTPUT_DIR/metadata/manifest.sha256"

if [ -d "$OUTPUT_DIR/datadirs" ]; then
    (
        cd "$OUTPUT_DIR/datadirs"
        # Use absolute path or redirect properly from subshell
        sha256sum *.tar 2>/dev/null || true
    ) > "$MANIFEST_FILE"

    if [ -f "$MANIFEST_FILE" ]; then
        log "  Checksums generated:"
        while IFS= read -r line; do
            log "    $line"
        done < "$MANIFEST_FILE"
    else
        log "  WARNING: Could not generate checksums"
        touch "$MANIFEST_FILE"
    fi
else
    log "  WARNING: Datadirs directory not found"
    touch "$MANIFEST_FILE"
fi

# ============================================================================
# STEP 3: Generate checkpoint.json
# ============================================================================

log "Generating checkpoint metadata..."

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SNAPSHOT_NAME="${ENCLAVE_NAME}-$(date -u +'%Y%m%d-%H%M%S')"

# Calculate datadir sizes
GETH_SIZE="0"
BEACON_SIZE="0"
VALIDATOR_SIZE="0"

if [ -f "$OUTPUT_DIR/datadirs/geth.tar" ]; then
    GETH_SIZE=$(stat -f%z "$OUTPUT_DIR/datadirs/geth.tar" 2>/dev/null || stat -c%s "$OUTPUT_DIR/datadirs/geth.tar" 2>/dev/null || echo "0")
fi

if [ -f "$OUTPUT_DIR/datadirs/lighthouse_beacon.tar" ]; then
    BEACON_SIZE=$(stat -f%z "$OUTPUT_DIR/datadirs/lighthouse_beacon.tar" 2>/dev/null || stat -c%s "$OUTPUT_DIR/datadirs/lighthouse_beacon.tar" 2>/dev/null || echo "0")
fi

if [ -f "$OUTPUT_DIR/datadirs/lighthouse_validator.tar" ]; then
    VALIDATOR_SIZE=$(stat -f%z "$OUTPUT_DIR/datadirs/lighthouse_validator.tar" 2>/dev/null || stat -c%s "$OUTPUT_DIR/datadirs/lighthouse_validator.tar" 2>/dev/null || echo "0")
fi

# Create checkpoint JSON
cat > "$OUTPUT_DIR/metadata/checkpoint.json" << EOF
{
  "snapshot_name": "$SNAPSHOT_NAME",
  "timestamp": "$TIMESTAMP",
  "enclave": {
    "name": "$ENCLAVE_NAME",
    "uuid": "$ENCLAVE_UUID"
  },
  "l1_state": {
    "block_number": "$BLOCK_NUMBER",
    "block_hash": "$BLOCK_HASH",
    "block_timestamp": "$BLOCK_TIMESTAMP",
    "genesis_hash": "$GENESIS_HASH"
  },
  "components": {
    "geth": {
      "container": "$GETH_CONTAINER",
      "image": "$GETH_IMAGE",
      "datadir_size": $GETH_SIZE
    },
    "beacon": {
      "container": "$BEACON_CONTAINER",
      "image": "$BEACON_IMAGE",
      "datadir_size": $BEACON_SIZE
    },
    "validator": {
      "container": "$VALIDATOR_CONTAINER",
      "image": "$VALIDATOR_IMAGE",
      "datadir_size": $VALIDATOR_SIZE
    }
  },
  "datadirs": [
    {
      "name": "geth.tar",
      "path": "datadirs/geth.tar",
      "size": $GETH_SIZE
    },
    {
      "name": "lighthouse_beacon.tar",
      "path": "datadirs/lighthouse_beacon.tar",
      "size": $BEACON_SIZE
    },
    {
      "name": "lighthouse_validator.tar",
      "path": "datadirs/lighthouse_validator.tar",
      "size": $VALIDATOR_SIZE
    }
  ],
  "verification": {
    "required_checks": [
      "initial_block_matches_checkpoint",
      "blocks_continue_progressing",
      "all_services_healthy"
    ]
  }
}
EOF

log "Checkpoint metadata generated: $OUTPUT_DIR/metadata/checkpoint.json"

# Pretty print the checkpoint
log "Checkpoint summary:"
jq -r '
  "  Snapshot: " + .snapshot_name,
  "  Timestamp: " + .timestamp,
  "  Block: " + .l1_state.block_number,
  "  Geth: " + .components.geth.image,
  "  Beacon: " + .components.beacon.image,
  "  Validator: " + .components.validator.image
' "$OUTPUT_DIR/metadata/checkpoint.json"

# ============================================================================
# STEP 4: Create snapshot info file
# ============================================================================

log "Creating snapshot info..."

cat > "$OUTPUT_DIR/SNAPSHOT_INFO.txt" << EOF
Ethereum L1 Snapshot
====================

Snapshot Name: $SNAPSHOT_NAME
Created: $TIMESTAMP
Enclave: $ENCLAVE_NAME ($ENCLAVE_UUID)

L1 State
--------
Block Number: $BLOCK_NUMBER
Block Hash: $BLOCK_HASH
Genesis Hash: $GENESIS_HASH

Components
----------
Geth: $GETH_IMAGE
Beacon: $BEACON_IMAGE
Validator: $VALIDATOR_IMAGE

Datadir Sizes
-------------
Geth: $(numfmt --to=iec $GETH_SIZE 2>/dev/null || echo "$GETH_SIZE bytes")
Beacon: $(numfmt --to=iec $BEACON_SIZE 2>/dev/null || echo "$BEACON_SIZE bytes")
Validator: $(numfmt --to=iec $VALIDATOR_SIZE 2>/dev/null || echo "$VALIDATOR_SIZE bytes")

Files
-----
$(find "$OUTPUT_DIR" -type f | sed "s|$OUTPUT_DIR/||" | sort)

Usage
-----
To verify this snapshot:
  ./snapshot/verify.sh $OUTPUT_DIR

To start this snapshot:
  cd $OUTPUT_DIR
  docker-compose -f docker-compose.snapshot.yml up -d

EOF

log "Snapshot info created: $OUTPUT_DIR/SNAPSHOT_INFO.txt"

log "Metadata generation complete!"

exit 0
