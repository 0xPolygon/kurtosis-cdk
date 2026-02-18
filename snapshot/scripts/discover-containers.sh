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

# Try label-based discovery first (including stopped containers)
GETH_CONTAINER=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --filter "label=com.kurtosistech.custom.ethereum-package.client-type=execution" \
    --format "{{.Names}}" | head -1)

if [ -z "$GETH_CONTAINER" ]; then
    # Fallback: name pattern matching (including stopped containers)
    GETH_CONTAINER=$(docker ps -a --format "{{.Names}}" | grep -E "el-.*-geth-lighthouse" | head -1)
fi

if [ -z "$GETH_CONTAINER" ]; then
    log "ERROR: Geth execution client not found"
    exit 1
fi

log "Found Geth: $GETH_CONTAINER"

# Discover Lighthouse Beacon
log "Discovering Lighthouse beacon node..."

# Try label-based discovery (including stopped containers)
BEACON_CONTAINER=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "cl-.*-lighthouse-geth" | head -1)

if [ -z "$BEACON_CONTAINER" ]; then
    # Fallback: name pattern matching (including stopped containers)
    BEACON_CONTAINER=$(docker ps -a --format "{{.Names}}" | grep -E "cl-.*-lighthouse-geth" | head -1)
fi

if [ -z "$BEACON_CONTAINER" ]; then
    log "ERROR: Lighthouse beacon node not found"
    exit 1
fi

log "Found Beacon: $BEACON_CONTAINER"

# Discover Lighthouse Validator (MANDATORY)
log "Discovering Lighthouse validator..."

# Try label-based discovery (including stopped containers)
VALIDATOR_CONTAINER=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "vc-.*-geth-lighthouse" | head -1)

if [ -z "$VALIDATOR_CONTAINER" ]; then
    # Fallback: name pattern matching (including stopped containers)
    VALIDATOR_CONTAINER=$(docker ps -a --format "{{.Names}}" | grep -E "vc-.*-geth-lighthouse" | head -1)
fi

if [ -z "$VALIDATOR_CONTAINER" ]; then
    log "ERROR: Lighthouse validator not found (MANDATORY)"
    log "Validators are required for snapshot creation"
    exit 1
fi

log "Found Validator: $VALIDATOR_CONTAINER"

# Discover Agglayer (OPTIONAL)
log "Discovering Agglayer..."

# Try label-based discovery (including stopped containers)
AGGLAYER_CONTAINER=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "^agglayer--" | head -1)

if [ -z "$AGGLAYER_CONTAINER" ]; then
    # Fallback: name pattern matching (including stopped containers)
    AGGLAYER_CONTAINER=$(docker ps -a --format "{{.Names}}" | grep -E "^agglayer--" | head -1)
fi

if [ -z "$AGGLAYER_CONTAINER" ]; then
    log "WARNING: Agglayer not found (optional component)"
    AGGLAYER_FOUND=false
else
    log "Found Agglayer: $AGGLAYER_CONTAINER"
    AGGLAYER_FOUND=true
fi

# ============================================================================
# Discover L2 Chains (op-geth + op-node) - OPTIONAL
# ============================================================================

log "Discovering L2 chains (op-geth based)..."

# Find all op-geth execution layer containers (including stopped)
# Pattern: op-el-{participant_id}-op-geth-op-node-{network_prefix}
OP_EL_CONTAINERS=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "^op-el-.*-op-geth-op-node" || true)

# Find all op-node consensus layer containers (including stopped)
# Pattern: op-cl-{participant_id}-op-node-op-geth-{network_prefix}
OP_CL_CONTAINERS=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "^op-cl-.*-op-node-op-geth" || true)

# Find all aggkit containers (including stopped)
# Pattern: aggkit-{network_prefix}
AGGKIT_CONTAINERS=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "^aggkit-" || true)

# Extract unique network prefixes from discovered containers
declare -A L2_NETWORKS
for container in $OP_EL_CONTAINERS $OP_CL_CONTAINERS $AGGKIT_CONTAINERS; do
    # Extract network prefix (e.g., "001" from "op-el-1-op-geth-op-node-001")
    if [[ "$container" =~ -([0-9]{3})--[a-f0-9]+$ ]]; then
        prefix="${BASH_REMATCH[1]}"
        L2_NETWORKS[$prefix]=1
    fi
done

# Process each discovered L2 network
L2_CHAINS_JSON=""
L2_COUNT=0

for prefix in "${!L2_NETWORKS[@]}"; do
    log "  Discovering L2 network: $prefix"

    # Find sequencer (participant 1)
    OP_EL_SEQ=$(echo "$OP_EL_CONTAINERS" | grep -E "^op-el-1-op-geth-op-node-$prefix--" | head -1 || true)
    OP_CL_SEQ=$(echo "$OP_CL_CONTAINERS" | grep -E "^op-cl-1-op-node-op-geth-$prefix--" | head -1 || true)

    # Find RPC node (participant 2) - optional
    OP_EL_RPC=$(echo "$OP_EL_CONTAINERS" | grep -E "^op-el-2-op-geth-op-node-$prefix--" | head -1 || true)
    OP_CL_RPC=$(echo "$OP_CL_CONTAINERS" | grep -E "^op-cl-2-op-node-op-geth-$prefix--" | head -1 || true)

    # Find aggkit for this network
    AGGKIT=$(echo "$AGGKIT_CONTAINERS" | grep -E "^aggkit-$prefix--" | head -1 || true)

    # Validate we have at least the sequencer components
    if [ -z "$OP_EL_SEQ" ] || [ -z "$OP_CL_SEQ" ]; then
        log "    WARNING: Incomplete L2 network $prefix (missing sequencer components), skipping"
        continue
    fi

    log "    ✓ op-geth sequencer: $OP_EL_SEQ"
    log "    ✓ op-node sequencer: $OP_CL_SEQ"

    if [ -n "$OP_EL_RPC" ]; then
        log "    ✓ op-geth rpc: $OP_EL_RPC"
    fi
    if [ -n "$OP_CL_RPC" ]; then
        log "    ✓ op-node rpc: $OP_CL_RPC"
    fi
    if [ -n "$AGGKIT" ]; then
        log "    ✓ aggkit: $AGGKIT"
    fi

    # Get container IDs and images
    OP_EL_SEQ_ID=$(docker inspect --format='{{.Id}}' "$OP_EL_SEQ")
    OP_CL_SEQ_ID=$(docker inspect --format='{{.Id}}' "$OP_CL_SEQ")
    OP_EL_SEQ_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$OP_EL_SEQ")
    OP_CL_SEQ_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$OP_CL_SEQ")

    # Build JSON for this L2 network
    L2_CHAIN_JSON=$(cat <<EOF
    "$prefix": {
      "prefix": "$prefix",
      "op_geth_sequencer": {
        "container_name": "$OP_EL_SEQ",
        "container_id": "$OP_EL_SEQ_ID",
        "image": "$OP_EL_SEQ_IMAGE"
      },
      "op_node_sequencer": {
        "container_name": "$OP_CL_SEQ",
        "container_id": "$OP_CL_SEQ_ID",
        "image": "$OP_CL_SEQ_IMAGE"
      }
EOF
)

    # Add RPC nodes if present
    if [ -n "$OP_EL_RPC" ]; then
        OP_EL_RPC_ID=$(docker inspect --format='{{.Id}}' "$OP_EL_RPC")
        OP_EL_RPC_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$OP_EL_RPC")
        L2_CHAIN_JSON+=",
      \"op_geth_rpc\": {
        \"container_name\": \"$OP_EL_RPC\",
        \"container_id\": \"$OP_EL_RPC_ID\",
        \"image\": \"$OP_EL_RPC_IMAGE\"
      }"
    fi

    if [ -n "$OP_CL_RPC" ]; then
        OP_CL_RPC_ID=$(docker inspect --format='{{.Id}}' "$OP_CL_RPC")
        OP_CL_RPC_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$OP_CL_RPC")
        L2_CHAIN_JSON+=",
      \"op_node_rpc\": {
        \"container_name\": \"$OP_CL_RPC\",
        \"container_id\": \"$OP_CL_RPC_ID\",
        \"image\": \"$OP_CL_RPC_IMAGE\"
      }"
    fi

    # Add aggkit if present
    if [ -n "$AGGKIT" ]; then
        AGGKIT_ID=$(docker inspect --format='{{.Id}}' "$AGGKIT")
        AGGKIT_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$AGGKIT")
        L2_CHAIN_JSON+=",
      \"aggkit\": {
        \"container_name\": \"$AGGKIT\",
        \"container_id\": \"$AGGKIT_ID\",
        \"image\": \"$AGGKIT_IMAGE\"
      }"
    fi

    L2_CHAIN_JSON+="
    }"

    # Append to L2_CHAINS_JSON with comma if not first
    if [ $L2_COUNT -gt 0 ]; then
        L2_CHAINS_JSON+=","
    fi
    L2_CHAINS_JSON+="$L2_CHAIN_JSON"
    L2_COUNT=$((L2_COUNT + 1))
done

if [ $L2_COUNT -gt 0 ]; then
    log "Found $L2_COUNT L2 network(s)"
else
    log "No L2 networks found (optional component)"
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

# Get network name from geth container
NETWORK_NAME=$(docker inspect "$GETH_CONTAINER" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')

log "Container IDs retrieved"
log "  Geth ID: ${GETH_ID:0:12}"
log "  Beacon ID: ${BEACON_ID:0:12}"
log "  Validator ID: ${VALIDATOR_ID:0:12}"
if [ "$AGGLAYER_FOUND" = true ]; then
    log "  Agglayer ID: ${AGGLAYER_ID:0:12}"
fi

# Verify containers exist and report their state
CONTAINERS_TO_CHECK="$GETH_CONTAINER $BEACON_CONTAINER $VALIDATOR_CONTAINER"
if [ "$AGGLAYER_FOUND" = true ]; then
    CONTAINERS_TO_CHECK="$CONTAINERS_TO_CHECK $AGGLAYER_CONTAINER"
fi

for container in $CONTAINERS_TO_CHECK; do
    state=$(docker inspect --format='{{.State.Status}}' "$container")
    log "  Container $container: $state"
done

# Write discovery results to JSON
# Build L2 chains section
L2_CHAINS_SECTION=""
if [ $L2_COUNT -gt 0 ]; then
    L2_CHAINS_SECTION=",
  \"l2_chains\": {
$L2_CHAINS_JSON
  }"
fi

# Build agglayer section
AGGLAYER_SECTION=""
if [ "$AGGLAYER_FOUND" = true ]; then
    AGGLAYER_SECTION="\"agglayer\": {
    \"container_name\": \"$AGGLAYER_CONTAINER\",
    \"container_id\": \"$AGGLAYER_ID\",
    \"image\": \"$AGGLAYER_IMAGE\",
    \"found\": true
  }"
else
    AGGLAYER_SECTION="\"agglayer\": {
    \"found\": false
  }"
fi

cat > "$OUTPUT_FILE" << EOF
{
  "enclave_name": "$ENCLAVE_NAME",
  "enclave_uuid": "$ENCLAVE_UUID",
  "network_name": "$NETWORK_NAME",
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
  $AGGLAYER_SECTION$L2_CHAINS_SECTION
}
EOF

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

if [ $L2_COUNT -gt 0 ]; then
    log "  L2 Networks: $L2_COUNT network(s) discovered"
    for prefix in "${!L2_NETWORKS[@]}"; do
        log "    Network $prefix:"
        # Show sequencer containers for this network
        for container in $OP_EL_CONTAINERS $OP_CL_CONTAINERS $AGGKIT_CONTAINERS; do
            if [[ "$container" =~ -$prefix-- ]]; then
                log "      - $container"
            fi
        done
    done
else
    log "  L2 Networks: Not found (optional)"
fi

exit 0
