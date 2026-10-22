#!/usr/bin/env bash
#
# Container Discovery Script
#
# Default flavor ("default"): locates geth, lighthouse beacon, and lighthouse
# validator containers (plus optional agglayer / op-reth L2s) for a Kurtosis
# enclave.
#
# Flavor "anvil-aggkit": locates the anvil-based dev-ui stack instead --
# anvil-001 (L1), l2-anvil-00X, agglayer, aggkit-00X (which also serves the
# bridge REST API -- there is no separate -bridge sibling container),
# aggkit-proxy-001, the bridge-ui haproxy and the dev-ui container.
#
# Usage: discover-containers.sh [--flavor <default|anvil-aggkit>] <ENCLAVE_NAME> <OUTPUT_FILE>
#

set -euo pipefail

# Parse arguments (two positionals; --flavor is optional and defaults to the
# pre-existing behaviour, so `discover-containers.sh <enclave> <out>` is
# unchanged).
FLAVOR="default"
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --flavor)
            FLAVOR="${2:-}"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--flavor <default|anvil-aggkit>] <ENCLAVE_NAME> <OUTPUT_FILE>" >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [ ${#POSITIONAL[@]} -ne 2 ]; then
    echo "Usage: $0 [--flavor <default|anvil-aggkit>] <ENCLAVE_NAME> <OUTPUT_FILE>" >&2
    exit 1
fi

case "$FLAVOR" in
    default|anvil-aggkit) ;;
    *)
        echo "ERROR: Unknown flavor: $FLAVOR (expected 'default' or 'anvil-aggkit')" >&2
        exit 1
        ;;
esac

ENCLAVE_NAME="${POSITIONAL[0]}"
OUTPUT_FILE="${POSITIONAL[1]}"

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

# ============================================================================
# Flavor: anvil-aggkit
#
# Everything below this block is the original ("default") geth/lighthouse
# discovery and is left untouched -- the anvil branch writes its own
# discovery.json and exits before reaching it.
# ============================================================================

# All kurtosis container names carry a "--<hash>" suffix, e.g.
# "aggkit-001--14eb470d2e0f48adb066955936950de5". Anchoring on that suffix is
# what keeps "aggkit-proxy-001--<hash>" from matching a bare "^aggkit-" prefix
# (the phantom-prefix bug this flavor must not repeat).
KURTOSIS_SUFFIX_RE='--[0-9a-f]+$'

# List enclave containers (running or stopped) whose name matches $1.
find_containers() {
    docker ps -a \
        --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
        --format "{{.Names}}" | grep -E "$1" || true
}

# {"<container-port>": "<host-port>", ...} for every published port.
container_ports_json() {
    docker inspect --format '{{json .NetworkSettings.Ports}}' "$1" \
        | jq -c '[to_entries[]
                  | select(.value != null and (.value | length) > 0)
                  | {key: (.key | sub("/(tcp|udp)$"; "")),
                     value: (.value[0].HostPort)}]
                 | from_entries'
}

# Full component record for a kurtosis container.
component_json() {
    local container="$1"
    local service_name="${container%%--*}"
    local id image state cmd entrypoint ports
    id=$(docker inspect --format='{{.Id}}' "$container")
    image=$(docker inspect --format='{{.Config.Image}}' "$container")
    state=$(docker inspect --format='{{.State.Status}}' "$container")
    cmd=$(docker inspect --format='{{json .Config.Cmd}}' "$container")
    entrypoint=$(docker inspect --format='{{json .Config.Entrypoint}}' "$container")
    ports=$(container_ports_json "$container")
    jq -n \
        --arg service_name "$service_name" \
        --arg container_name "$container" \
        --arg container_id "$id" \
        --arg image "$image" \
        --arg state "$state" \
        --argjson cmd "$cmd" \
        --argjson entrypoint "$entrypoint" \
        --argjson ports "$ports" \
        '{found: true, service_name: $service_name, container_name: $container_name,
          container_id: $container_id, image: $image, state: $state,
          entrypoint: $entrypoint, cmd: $cmd, ports: $ports}'
}

NOT_FOUND_JSON='{"found": false}'

# eth_chainId (decimal) for an anvil container, or null if unreachable.
anvil_chain_id() {
    local container="$1"
    local host_port hex
    host_port=$(docker port "$container" 8545 2>/dev/null | head -1 | rev | cut -d: -f1 | rev)
    if [ -z "$host_port" ]; then
        echo "null"
        return 0
    fi
    hex=$(curl -s --max-time 10 "http://127.0.0.1:$host_port" \
        -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // empty')
    if [ -z "$hex" ]; then
        echo "null"
    else
        echo $((16#${hex#0x}))
    fi
}

if [ "$FLAVOR" = "anvil-aggkit" ]; then
    log "Flavor: anvil-aggkit"

    # ---- L1 anvil (mandatory) ----------------------------------------------
    L1_ANVIL=$(find_containers "^anvil-[0-9]{3}$KURTOSIS_SUFFIX_RE" | head -1)
    if [ -z "$L1_ANVIL" ]; then
        log "ERROR: L1 anvil container (anvil-00X) not found in enclave $ENCLAVE_NAME"
        exit 1
    fi
    log "Found L1 anvil: $L1_ANVIL"
    L1_JSON=$(component_json "$L1_ANVIL")
    L1_CHAIN_ID=$(anvil_chain_id "$L1_ANVIL")
    L1_JSON=$(echo "$L1_JSON" | jq --argjson chain_id "$L1_CHAIN_ID" '. + {chain_id: $chain_id}')
    log "  L1 chain id: $L1_CHAIN_ID"

    # ---- L2 anvils (mandatory, one or more) --------------------------------
    # The L2 prefix set is derived from the l2-anvil containers ONLY. It is
    # deliberately NOT derived from "^aggkit-" (which also matches
    # aggkit-proxy-001--<hash> and would register a phantom L2).
    L2_ANVIL_CONTAINERS=$(find_containers "^l2-anvil-[0-9]{3}$KURTOSIS_SUFFIX_RE" | sort)
    if [ -z "$L2_ANVIL_CONTAINERS" ]; then
        log "ERROR: no L2 anvil containers (l2-anvil-00X) found in enclave $ENCLAVE_NAME"
        exit 1
    fi

    L2_CHAINS_JSON='{}'
    L2_COUNT=0
    for container in $L2_ANVIL_CONTAINERS; do
        service_name="${container%%--*}"
        prefix="${service_name##*-}"
        log "  Discovering L2 network: $prefix"

        l2_json=$(component_json "$container")
        chain_id=$(anvil_chain_id "$container")
        l2_json=$(echo "$l2_json" | jq --argjson chain_id "$chain_id" '. + {chain_id: $chain_id}')
        log "    ✓ l2 anvil: $container (chain id $chain_id)"

        # aggkit-<prefix>--<hash>, NOT aggkit-proxy-<prefix>--<hash>: excluded
        # by anchoring the kurtosis hash suffix directly after the numeric
        # prefix. This same container now also serves the bridge REST API
        # (--components=...,bridge) -- there is no separate -bridge sibling.
        aggkit=$(find_containers "^aggkit-$prefix$KURTOSIS_SUFFIX_RE" | head -1)

        if [ -z "$aggkit" ]; then
            log "ERROR: aggkit-$prefix not found for L2 network $prefix"
            exit 1
        fi
        log "    ✓ aggkit: $aggkit"
        aggkit_json=$(component_json "$aggkit")

        L2_CHAINS_JSON=$(echo "$L2_CHAINS_JSON" | jq \
            --arg prefix "$prefix" \
            --argjson anvil "$l2_json" \
            --argjson aggkit "$aggkit_json" \
            '.[$prefix] = {prefix: $prefix, anvil: $anvil, aggkit: $aggkit}')
        L2_COUNT=$((L2_COUNT + 1))
    done
    log "Found $L2_COUNT L2 network(s)"

    # ---- agglayer (mandatory for this flavor) ------------------------------
    AGGLAYER_CONTAINER=$(find_containers "^agglayer$KURTOSIS_SUFFIX_RE" | head -1)
    if [ -z "$AGGLAYER_CONTAINER" ]; then
        log "ERROR: agglayer not found in enclave $ENCLAVE_NAME"
        exit 1
    fi
    log "Found agglayer: $AGGLAYER_CONTAINER"
    AGGLAYER_JSON=$(component_json "$AGGLAYER_CONTAINER")

    # ---- aggkit-proxy (proxy,tracker) --------------------------------------
    AGGKIT_PROXY_CONTAINER=$(find_containers "^aggkit-proxy-[0-9]{3}$KURTOSIS_SUFFIX_RE" | head -1)
    if [ -n "$AGGKIT_PROXY_CONTAINER" ]; then
        log "Found aggkit-proxy: $AGGKIT_PROXY_CONTAINER"
        AGGKIT_PROXY_JSON=$(component_json "$AGGKIT_PROXY_CONTAINER")
    else
        log "WARNING: aggkit-proxy not found (dev-ui tracker routes will be unavailable)"
        AGGKIT_PROXY_JSON="$NOT_FOUND_JSON"
    fi

    # ---- bridge-ui haproxy (the single CORS origin) ------------------------
    HAPROXY_CONTAINER=$(find_containers "^agglayer-dev-ui-proxy-[0-9]{3}$KURTOSIS_SUFFIX_RE" | head -1)
    if [ -n "$HAPROXY_CONTAINER" ]; then
        log "Found bridge-ui haproxy: $HAPROXY_CONTAINER"
        HAPROXY_JSON=$(component_json "$HAPROXY_CONTAINER")
    else
        log "WARNING: bridge-ui haproxy not found (dev-ui has no CORS origin)"
        HAPROXY_JSON="$NOT_FOUND_JSON"
    fi

    # ---- dev-ui ------------------------------------------------------------
    # "^agglayer-dev-ui-[0-9]{3}--" cannot match the haproxy above, whose name
    # is "agglayer-dev-ui-proxy-00X--<hash>".
    DEV_UI_CONTAINER=$(find_containers "^agglayer-dev-ui-[0-9]{3}$KURTOSIS_SUFFIX_RE" | head -1)
    if [ -n "$DEV_UI_CONTAINER" ]; then
        log "Found dev-ui: $DEV_UI_CONTAINER"
        DEV_UI_JSON=$(component_json "$DEV_UI_CONTAINER")
    else
        log "WARNING: dev-ui container not found"
        DEV_UI_JSON="$NOT_FOUND_JSON"
    fi

    NETWORK_NAME=$(docker inspect "$L1_ANVIL" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')

    jq -n \
        --arg flavor "$FLAVOR" \
        --arg enclave_name "$ENCLAVE_NAME" \
        --arg enclave_uuid "$ENCLAVE_UUID" \
        --arg network_name "$NETWORK_NAME" \
        --argjson l1_anvil "$L1_JSON" \
        --argjson l2_chains "$L2_CHAINS_JSON" \
        --argjson agglayer "$AGGLAYER_JSON" \
        --argjson aggkit_proxy "$AGGKIT_PROXY_JSON" \
        --argjson haproxy "$HAPROXY_JSON" \
        --argjson dev_ui "$DEV_UI_JSON" \
        '{flavor: $flavor,
          enclave_name: $enclave_name,
          enclave_uuid: $enclave_uuid,
          network_name: $network_name,
          l1_anvil: $l1_anvil,
          l2_chains: $l2_chains,
          agglayer: $agglayer,
          aggkit_proxy: $aggkit_proxy,
          haproxy: $haproxy,
          dev_ui: $dev_ui}
         | . + {components: ([.l1_anvil, .agglayer, .aggkit_proxy, .haproxy, .dev_ui]
                             + ([.l2_chains[] | .anvil, .aggkit])
                             | map(select(.found == true) | .service_name))}' \
        > "$OUTPUT_FILE"

    log "Discovery complete. Results written to: $OUTPUT_FILE"
    log "Components ($(jq -r '.components | length' "$OUTPUT_FILE")):"
    jq -r '.components[] | "  - " + .' "$OUTPUT_FILE" >&2

    # Guard against a component being listed twice (the phantom-prefix class of
    # bug): every service name must appear exactly once.
    DUPES=$(jq -r '.components | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' "$OUTPUT_FILE")
    if [ -n "$DUPES" ]; then
        log "ERROR: duplicate components in discovery output: $DUPES"
        exit 1
    fi

    exit 0
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
# Discover L2 Chains (op-reth + op-node) - OPTIONAL
# ============================================================================

log "Discovering L2 chains (op-reth based)..."

# Find all op-reth execution layer containers (including stopped)
# Pattern: op-el-{participant_id}-op-reth-op-node-{network_prefix}
OP_EL_CONTAINERS=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "^op-el-.*-op-reth-op-node" || true)

# Find all op-node consensus layer containers (including stopped)
# Pattern: op-cl-{participant_id}-op-node-op-reth-{network_prefix}
OP_CL_CONTAINERS=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "^op-cl-.*-op-node-op-reth" || true)

# Find all aggkit containers (including stopped)
# Pattern: aggkit-{network_prefix}
#
# NOTE: "^aggkit-" also matches "aggkit-proxy-00X--<hash>", which then feeds a
# phantom network prefix into L2_NETWORKS below. On this (default) flavor that
# is inert -- a prefix with no op-el/op-cl sequencer is dropped by the
# "Incomplete L2 network" guard, so discovery.json is unaffected and only a log
# line is emitted. It is NOT inert on the anvil-aggkit flavor, where
# aggkit-proxy-001 sits next to a real aggkit-001; that branch anchors the
# kurtosis "--<hash>" suffix directly after the numeric prefix instead. Left
# as-is here deliberately: changing it would alter default-flavor output.
AGGKIT_CONTAINERS=$(docker ps -a \
    --filter "label=com.kurtosistech.enclave-id=$ENCLAVE_UUID" \
    --format "{{.Names}}" | grep -E "^aggkit-" || true)

# Extract unique network prefixes from discovered containers
declare -A L2_NETWORKS
for container in $OP_EL_CONTAINERS $OP_CL_CONTAINERS $AGGKIT_CONTAINERS; do
    # Extract network prefix (e.g., "001" from "op-el-1-op-reth-op-node-001")
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
    OP_EL_SEQ=$(echo "$OP_EL_CONTAINERS" | grep -E "^op-el-1-op-reth-op-node-$prefix--" | head -1 || true)
    OP_CL_SEQ=$(echo "$OP_CL_CONTAINERS" | grep -E "^op-cl-1-op-node-op-reth-$prefix--" | head -1 || true)

    # Find RPC node (participant 2) - optional
    OP_EL_RPC=$(echo "$OP_EL_CONTAINERS" | grep -E "^op-el-2-op-reth-op-node-$prefix--" | head -1 || true)
    OP_CL_RPC=$(echo "$OP_CL_CONTAINERS" | grep -E "^op-cl-2-op-node-op-reth-$prefix--" | head -1 || true)

    # Find aggkit for this network
    AGGKIT=$(echo "$AGGKIT_CONTAINERS" | grep -E "^aggkit-$prefix--" | head -1 || true)

    # Validate we have at least the sequencer components
    if [ -z "$OP_EL_SEQ" ] || [ -z "$OP_CL_SEQ" ]; then
        log "    WARNING: Incomplete L2 network $prefix (missing sequencer components), skipping"
        continue
    fi

    log "    ✓ op-reth sequencer: $OP_EL_SEQ"
    log "    ✓ op-node sequencer: $OP_CL_SEQ"

    if [ -n "$OP_EL_RPC" ]; then
        log "    ✓ op-reth rpc: $OP_EL_RPC"
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
      "op_reth_sequencer": {
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
      \"op_reth_rpc\": {
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
