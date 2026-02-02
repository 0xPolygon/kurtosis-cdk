#!/usr/bin/env bash
#
# Container Discovery Script
# Locates geth, lighthouse beacon, and lighthouse validator containers for a Kurtosis enclave
#
# Usage: discover-containers.sh <ENCLAVE_NAME> <OUTPUT_FILE>
#

set -euo pipefail

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <ENCLAVE_NAME> <OUTPUT_FILE>" >&2
    exit 1
fi

ENCLAVE_NAME="$1"
OUTPUT_FILE="$2"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log "Starting container discovery for enclave: $ENCLAVE_NAME"

# Validate enclave exists
if ! kurtosis enclave ls | grep -q "$ENCLAVE_NAME"; then
    log "ERROR: Enclave '$ENCLAVE_NAME' not found"
    log "Available enclaves:"
    kurtosis enclave ls | tail -n +2 | awk '{print "  - " $2}'
    exit 1
fi

# Get enclave UUID (short and full versions)
ENCLAVE_UUID_SHORT=$(kurtosis enclave ls | grep "$ENCLAVE_NAME" | awk '{print $1}')
log "Enclave UUID (short): $ENCLAVE_UUID_SHORT"

# Find any container from this enclave to get the full UUID
ENCLAVE_UUID=""
for cid in $(docker ps -q); do
    enc_id=$(docker inspect "$cid" --format '{{index .Config.Labels "com.kurtosistech.enclave-id"}}' 2>/dev/null || echo "")
    if [[ "$enc_id" == "$ENCLAVE_UUID_SHORT"* ]]; then
        ENCLAVE_UUID="$enc_id"
        break
    fi
done

if [ -z "$ENCLAVE_UUID" ]; then
    log "WARNING: Could not determine full enclave UUID, using short version"
    ENCLAVE_UUID="$ENCLAVE_UUID_SHORT"
else
    log "Enclave UUID (full): $ENCLAVE_UUID"
fi

# Discovery using Kurtosis labels (most reliable method)
# Containers have labels like:
#   com.kurtosistech.enclave-id=<UUID>
#   com.kurtosistech.custom.ethereum-package.client-type=execution|beacon|validator

# Discover Geth (Execution Layer)
log "Discovering Geth execution client..."

# Try label-based discovery first
GETH_CONTAINER=$(docker ps \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --filter "label=com.kurtosistech.custom.ethereum-package.client-type=execution" \
    --format "{{.Names}}" | head -1)

if [ -z "$GETH_CONTAINER" ]; then
    # Fallback: name pattern matching
    GETH_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "el-.*-geth-lighthouse" | head -1)
fi

if [ -z "$GETH_CONTAINER" ]; then
    log "ERROR: Geth execution client not found"
    exit 1
fi

log "Found Geth: $GETH_CONTAINER"

# Discover Lighthouse Beacon
log "Discovering Lighthouse beacon node..."

# Try label-based discovery
BEACON_CONTAINER=$(docker ps \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "cl-.*-lighthouse-geth" | head -1)

if [ -z "$BEACON_CONTAINER" ]; then
    # Fallback: name pattern matching
    BEACON_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "cl-.*-lighthouse-geth" | head -1)
fi

if [ -z "$BEACON_CONTAINER" ]; then
    log "ERROR: Lighthouse beacon node not found"
    exit 1
fi

log "Found Beacon: $BEACON_CONTAINER"

# Discover Lighthouse Validator (MANDATORY)
log "Discovering Lighthouse validator..."

# Try label-based discovery
VALIDATOR_CONTAINER=$(docker ps \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "vc-.*-geth-lighthouse" | head -1)

if [ -z "$VALIDATOR_CONTAINER" ]; then
    # Fallback: name pattern matching
    VALIDATOR_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "vc-.*-geth-lighthouse" | head -1)
fi

if [ -z "$VALIDATOR_CONTAINER" ]; then
    log "ERROR: Lighthouse validator not found (MANDATORY)"
    log "Validators are required for snapshot creation"
    exit 1
fi

log "Found Validator: $VALIDATOR_CONTAINER"

# Discover Agglayer (OPTIONAL)
log "Discovering Agglayer..."

# Try label-based discovery
AGGLAYER_CONTAINER=$(docker ps \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "^agglayer--" | head -1)

if [ -z "$AGGLAYER_CONTAINER" ]; then
    # Fallback: name pattern matching
    AGGLAYER_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "^agglayer--" | head -1)
fi

if [ -z "$AGGLAYER_CONTAINER" ]; then
    log "WARNING: Agglayer not found (optional component)"
    AGGLAYER_FOUND=false
else
    log "Found Agglayer: $AGGLAYER_CONTAINER"
    AGGLAYER_FOUND=true
fi

# Get container IDs
GETH_ID=$(docker inspect --format='{{.Id}}' "$GETH_CONTAINER")
BEACON_ID=$(docker inspect --format='{{.Id}}' "$BEACON_CONTAINER")
VALIDATOR_ID=$(docker inspect --format='{{.Id}}' "$VALIDATOR_CONTAINER")

if [ "$AGGLAYER_FOUND" = true ]; then
    AGGLAYER_ID=$(docker inspect --format='{{.Id}}' "$AGGLAYER_CONTAINER")
fi

# Get image versions
GETH_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$GETH_CONTAINER")
BEACON_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$BEACON_CONTAINER")
VALIDATOR_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$VALIDATOR_CONTAINER")

if [ "$AGGLAYER_FOUND" = true ]; then
    AGGLAYER_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$AGGLAYER_CONTAINER")
fi

log "Container IDs retrieved"
log "  Geth ID: ${GETH_ID:0:12}"
log "  Beacon ID: ${BEACON_ID:0:12}"
log "  Validator ID: ${VALIDATOR_ID:0:12}"
if [ "$AGGLAYER_FOUND" = true ]; then
    log "  Agglayer ID: ${AGGLAYER_ID:0:12}"
fi

# Verify containers are running
CONTAINERS_TO_CHECK="$GETH_CONTAINER $BEACON_CONTAINER $VALIDATOR_CONTAINER"
if [ "$AGGLAYER_FOUND" = true ]; then
    CONTAINERS_TO_CHECK="$CONTAINERS_TO_CHECK $AGGLAYER_CONTAINER"
fi

for container in $CONTAINERS_TO_CHECK; do
    state=$(docker inspect --format='{{.State.Status}}' "$container")
    if [ "$state" != "running" ]; then
        log "WARNING: Container $container is not running (state: $state)"
    fi
done

# Write discovery results to JSON
if [ "$AGGLAYER_FOUND" = true ]; then
    cat > "$OUTPUT_FILE" << EOF
{
  "enclave_name": "$ENCLAVE_NAME",
  "enclave_uuid": "$ENCLAVE_UUID",
  "geth": {
    "container_name": "$GETH_CONTAINER",
    "container_id": "$GETH_ID",
    "image": "$GETH_IMAGE"
  },
  "beacon": {
    "container_name": "$BEACON_CONTAINER",
    "container_id": "$BEACON_ID",
    "image": "$BEACON_IMAGE"
  },
  "validator": {
    "container_name": "$VALIDATOR_CONTAINER",
    "container_id": "$VALIDATOR_ID",
    "image": "$VALIDATOR_IMAGE"
  },
  "agglayer": {
    "container_name": "$AGGLAYER_CONTAINER",
    "container_id": "$AGGLAYER_ID",
    "image": "$AGGLAYER_IMAGE",
    "found": true
  }
}
EOF
else
    cat > "$OUTPUT_FILE" << EOF
{
  "enclave_name": "$ENCLAVE_NAME",
  "enclave_uuid": "$ENCLAVE_UUID",
  "geth": {
    "container_name": "$GETH_CONTAINER",
    "container_id": "$GETH_ID",
    "image": "$GETH_IMAGE"
  },
  "beacon": {
    "container_name": "$BEACON_CONTAINER",
    "container_id": "$BEACON_ID",
    "image": "$BEACON_IMAGE"
  },
  "validator": {
    "container_name": "$VALIDATOR_CONTAINER",
    "container_id": "$VALIDATOR_ID",
    "image": "$VALIDATOR_IMAGE"
  },
  "agglayer": {
    "found": false
  }
}
EOF
fi

log "Discovery complete. Results written to: $OUTPUT_FILE"
log "Summary:"
log "  Geth: $GETH_CONTAINER ($GETH_IMAGE)"
log "  Beacon: $BEACON_CONTAINER ($BEACON_IMAGE)"
log "  Validator: $VALIDATOR_CONTAINER ($VALIDATOR_IMAGE)"
if [ "$AGGLAYER_FOUND" = true ]; then
    log "  Agglayer: $AGGLAYER_CONTAINER ($AGGLAYER_IMAGE)"
else
    log "  Agglayer: Not found (optional)"
fi

exit 0
