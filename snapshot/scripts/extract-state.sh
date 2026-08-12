#!/usr/bin/env bash
#
# State Extraction Script
#
# Default flavor ("default"): stops the L1 containers and extracts their
# datadirs (geth/lighthouse), plus agglayer and op-reth L2 configuration.
#
# Flavor "anvil-aggkit": captures state from the three anvils over the
# `anvil_dumpState` RPC -- WITHOUT stopping anything -- plus the configs and
# keystores of the stateless services (agglayer, aggkit x2 (+ -bridge),
# aggkit-proxy, haproxy, dev-ui). The L2 anvils are launched with `--init`,
# which anvil refuses to combine with `--dump-state`, so RPC capture is the
# only option there; the L1 anvil is captured the same way for symmetry and
# because `--dump-state` only writes its file on shutdown.
#
# The dump is taken with `anvil_dumpState(preserve_historical_states = true)`
# (S9b). Without it, `--load-state` restores every block/tx/receipt/log but
# only ONE state -- the tip -- so any `eth_call`/`eth_getCode`/
# `eth_getTransactionCount` pinned to a pre-snapshot block fails with
# `BlockOutOfRangeError`. That broke aggkit (rollupCreationBlockNumber) and
# agglayer (settlement-signer nonce-inclusion probe) on every restored
# bundle. With historical states preserved the restored chain answers state
# reads at every captured height, so no config repointing is needed.
#
# Usage: extract-state.sh [--flavor <default|anvil-aggkit>] <DISCOVERY_JSON> <OUTPUT_DIR>
#
# The flavor defaults to the `flavor` field of DISCOVERY_JSON when present,
# and to "default" otherwise, so existing two-argument callers are unaffected.
#

set -euo pipefail

# Check arguments
FLAVOR=""
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --flavor)
            FLAVOR="${2:-}"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--flavor <default|anvil-aggkit>] <DISCOVERY_JSON> <OUTPUT_DIR>" >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [ ${#POSITIONAL[@]} -ne 2 ]; then
    echo "Usage: $0 [--flavor <default|anvil-aggkit>] <DISCOVERY_JSON> <OUTPUT_DIR>" >&2
    exit 1
fi

DISCOVERY_JSON="${POSITIONAL[0]}"
OUTPUT_DIR="${POSITIONAL[1]}"

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

if [ -z "$FLAVOR" ]; then
    FLAVOR=$(jq -r '.flavor // "default"' "$DISCOVERY_JSON")
fi

case "$FLAVOR" in
    default|anvil-aggkit) ;;
    *)
        log "ERROR: Unknown flavor: $FLAVOR (expected 'default' or 'anvil-aggkit')"
        exit 1
        ;;
esac

# ============================================================================
# Flavor: anvil-aggkit
#
# Everything below this block is the original ("default") geth/lighthouse
# extraction and is left untouched -- the anvil branch writes its own output
# tree and exits before reaching it.
# ============================================================================

# Decode an `anvil_dumpState` result (0x-prefixed hex of a gzipped state JSON;
# older anvils returned the JSON uncompressed, which is handled too) into a
# plain JSON file.
decode_dump_state() {
    local hex_file="$1" out_file="$2"
    local magic decoder

    # Strip the 0x prefix in place.
    tail -c +3 "$hex_file" | tr -d '\n' > "$hex_file.stripped"
    mv "$hex_file.stripped" "$hex_file"

    magic=$(head -c 4 "$hex_file")

    if command -v xxd &> /dev/null; then
        decoder="xxd_decode"
    elif command -v python3 &> /dev/null; then
        decoder="python_decode"
    else
        log "ERROR: neither 'xxd' nor 'python3' available to decode the anvil state dump" >&2
        return 1
    fi

    if [ "$magic" = "1f8b" ]; then
        "$decoder" "$hex_file" | gzip -dc > "$out_file"
    else
        "$decoder" "$hex_file" > "$out_file"
    fi
}

# shellcheck disable=SC2317 # invoked indirectly via "$decoder" in decode_dump_state
xxd_decode() {
    xxd -r -p "$1"
}

# shellcheck disable=SC2317 # invoked indirectly via "$decoder" in decode_dump_state
python_decode() {
    python3 -c 'import sys
with open(sys.argv[1]) as f:
    sys.stdout.buffer.write(bytes.fromhex(f.read().strip()))' "$1"
}

# capture_anvil_state <container> <host_port> <out_json> -> block number on stdout
capture_anvil_state() {
    local container="$1" host_port="$2" out_file="$3"
    local rpc="http://127.0.0.1:$host_port"
    local tmp_response block_hex accounts

    tmp_response=$(mktemp "${TMPDIR:-/tmp}/anvil-dump-XXXXXX.json")

    block_hex=$(curl -s --max-time 30 "$rpc" -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // empty')
    if [ -z "$block_hex" ]; then
        log "    ERROR: $container is not answering JSON-RPC on $rpc" >&2
        rm -f "$tmp_response"
        return 1
    fi

    # anvil_dumpState is the ONLY capture route available here: the L2 anvils
    # run with `--init <genesis>`, and anvil rejects `--init` together with
    # `--dump-state`.
    #
    # params[0] = preserve_historical_states. MUST stay `true` (S9b): it is
    # what makes the restored chain serve `eth_call`/`eth_getCode`/
    # `eth_getTransactionCount` at pre-snapshot heights. Cost is roughly
    # `blocks x tip-state-size` of JSON, which is why capture must happen
    # right after enclave readiness (a few hundred blocks), never against a
    # long-lived enclave.
    if ! curl -s --max-time 300 "$rpc" -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"anvil_dumpState","params":[true],"id":1}' -o "$tmp_response"; then
        log "    ERROR: anvil_dumpState request to $container failed" >&2
        rm -f "$tmp_response"
        return 1
    fi

    if ! jq -e '.result | type == "string"' "$tmp_response" > /dev/null 2>&1; then
        log "    ERROR: anvil_dumpState on $container returned no result: $(head -c 400 "$tmp_response")" >&2
        rm -f "$tmp_response"
        return 1
    fi

    jq -j '.result' "$tmp_response" > "$tmp_response.hex"
    rm -f "$tmp_response"

    if ! decode_dump_state "$tmp_response.hex" "$out_file"; then
        rm -f "$tmp_response.hex"
        return 1
    fi
    rm -f "$tmp_response.hex"

    if [ ! -s "$out_file" ]; then
        log "    ERROR: decoded state for $container is empty" >&2
        return 1
    fi

    accounts=$(jq -r '.accounts | length' "$out_file" 2>/dev/null || echo "")
    if [ -z "$accounts" ] || [ "$accounts" = "null" ] || [ "$accounts" -eq 0 ]; then
        log "    ERROR: decoded state for $container has no accounts (not a valid anvil dump)" >&2
        return 1
    fi

    # S9b: historical states are load-bearing, not a nice-to-have -- without
    # them agglayer panics at settlement_task.rs and aggkit dies at startup on
    # the restored bundle. Fail the capture loudly rather than ship a bundle
    # that cannot settle.
    local historical
    historical=$(jq -r '.historical_states | if . == null then 0 else length end' "$out_file" 2>/dev/null || echo "0")
    if [ -z "$historical" ] || [ "$historical" = "null" ] || [ "$historical" -eq 0 ]; then
        log "    ERROR: decoded state for $container has NO historical_states." >&2
        log "           anvil_dumpState(true) is required so the restored chain can serve" >&2
        log "           state reads at pre-snapshot heights (see S9b). Is the anvil image" >&2
        log "           too old to support preserve_historical_states?" >&2
        return 1
    fi

    log "    ✓ $(basename "$out_file"): $(du -h "$out_file" | cut -f1), $accounts accounts, $historical historical states, block $((16#${block_hex#0x}))" >&2
    echo $((16#${block_hex#0x}))
}

# copy_container_dir <container> <src-dir> <dest-dir>
# Both copy helpers return non-zero on failure, which aborts the run under
# `set -e`; call them with `|| true` for anything genuinely optional.
copy_container_dir() {
    local container="$1" src="$2" dest="$3"
    rm -rf "$dest"
    if docker cp "$container:$src" "$dest" 2>/dev/null; then
        log "    ✓ $src -> $(basename "$dest")/ ($(find "$dest" -type f | wc -l) file(s))"
        return 0
    fi
    log "    ERROR: could not copy $src from $container"
    return 1
}

# copy_container_file <container> <src-file> <dest-file>
copy_container_file() {
    local container="$1" src="$2" dest="$3"
    mkdir -p "$(dirname "$dest")"
    if docker cp "$container:$src" "$dest" 2>/dev/null; then
        log "    ✓ $(basename "$dest") ($(wc -c < "$dest") bytes)"
        return 0
    fi
    log "    ERROR: could not copy $src from $container"
    return 1
}

if [ "$FLAVOR" = "anvil-aggkit" ]; then
    log "Flavor: anvil-aggkit (live capture -- no containers are stopped)"

    ENCLAVE_NAME=$(jq -r '.enclave_name' "$DISCOVERY_JSON")
    STATE_DIR="$OUTPUT_DIR/state"
    CONFIG_DIR="$OUTPUT_DIR/config"
    mkdir -p "$STATE_DIR" "$CONFIG_DIR"

    CHAINS_META='[]'

    # ---- L1 anvil ----------------------------------------------------------
    log "Capturing L1 anvil state..."
    L1_CONTAINER=$(jq -r '.l1_anvil.container_name' "$DISCOVERY_JSON")
    L1_SERVICE=$(jq -r '.l1_anvil.service_name' "$DISCOVERY_JSON")
    L1_PORT=$(jq -r '.l1_anvil.ports["8545"] // empty' "$DISCOVERY_JSON")
    if [ -z "$L1_PORT" ]; then
        log "ERROR: L1 anvil has no published 8545 port"
        exit 1
    fi
    L1_BLOCK=$(capture_anvil_state "$L1_CONTAINER" "$L1_PORT" "$STATE_DIR/$L1_SERVICE.json")
    CHAINS_META=$(echo "$CHAINS_META" | jq \
        --arg service "$L1_SERVICE" \
        --arg role "l1" \
        --arg state_file "state/$L1_SERVICE.json" \
        --argjson chain_id "$(jq '.l1_anvil.chain_id // null' "$DISCOVERY_JSON")" \
        --argjson network_id 0 \
        --argjson block_number "$L1_BLOCK" \
        --arg image "$(jq -r '.l1_anvil.image' "$DISCOVERY_JSON")" \
        --argjson cmd "$(jq '.l1_anvil.cmd' "$DISCOVERY_JSON")" \
        '. + [{service: $service, role: $role, chain_id: $chain_id, network_id: $network_id,
               block_number: $block_number, state_file: $state_file, image: $image, cmd: $cmd}]')

    # ---- L2 anvils ---------------------------------------------------------
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON"); do
        log "Capturing L2 anvil state (network $prefix)..."
        L2_CONTAINER=$(jq -r ".l2_chains[\"$prefix\"].anvil.container_name" "$DISCOVERY_JSON")
        L2_SERVICE=$(jq -r ".l2_chains[\"$prefix\"].anvil.service_name" "$DISCOVERY_JSON")
        L2_PORT=$(jq -r ".l2_chains[\"$prefix\"].anvil.ports[\"8545\"] // empty" "$DISCOVERY_JSON")
        if [ -z "$L2_PORT" ]; then
            log "ERROR: $L2_SERVICE has no published 8545 port"
            exit 1
        fi
        L2_BLOCK=$(capture_anvil_state "$L2_CONTAINER" "$L2_PORT" "$STATE_DIR/$L2_SERVICE.json")

        # The `--init` genesis is not part of the state dump; keep it so the
        # restore can reproduce the same launch shape if it wants to.
        L2_GENESIS_PATH=$(jq -r ".l2_chains[\"$prefix\"].anvil.cmd | join(\" \")" "$DISCOVERY_JSON" \
            | grep -oE '\-\-init +[^ ]+' | awk '{print $2}' | head -1)
        if [ -n "$L2_GENESIS_PATH" ]; then
            copy_container_file "$L2_CONTAINER" "$L2_GENESIS_PATH" "$STATE_DIR/$L2_SERVICE-genesis.json" || true
        fi

        CHAINS_META=$(echo "$CHAINS_META" | jq \
            --arg service "$L2_SERVICE" \
            --arg role "l2" \
            --arg prefix "$prefix" \
            --arg state_file "state/$L2_SERVICE.json" \
            --argjson chain_id "$(jq ".l2_chains[\"$prefix\"].anvil.chain_id // null" "$DISCOVERY_JSON")" \
            --argjson block_number "$L2_BLOCK" \
            --arg image "$(jq -r ".l2_chains[\"$prefix\"].anvil.image" "$DISCOVERY_JSON")" \
            --argjson cmd "$(jq ".l2_chains[\"$prefix\"].anvil.cmd" "$DISCOVERY_JSON")" \
            '. + [{service: $service, role: $role, prefix: $prefix, chain_id: $chain_id,
                   network_id: null, block_number: $block_number, state_file: $state_file,
                   image: $image, cmd: $cmd}]')
    done

    # ---- agglayer config ---------------------------------------------------
    log "Extracting agglayer configuration..."
    AGGLAYER_CONTAINER=$(jq -r '.agglayer.container_name' "$DISCOVERY_JSON")
    mkdir -p "$CONFIG_DIR/agglayer"
    copy_container_file "$AGGLAYER_CONTAINER" "/etc/agglayer/config.toml" "$CONFIG_DIR/agglayer/config.toml"
    copy_container_file "$AGGLAYER_CONTAINER" "/etc/agglayer/aggregator.keystore" "$CONFIG_DIR/agglayer/aggregator.keystore"
    log "  Note: /etc/agglayer/storage and /etc/agglayer/backups NOT extracted (stateless by design)"

    # ---- aggkit configs ----------------------------------------------------
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON"); do
        for role in aggkit aggkit_bridge; do
            found=$(jq -r ".l2_chains[\"$prefix\"].$role.found // false" "$DISCOVERY_JSON")
            if [ "$found" != "true" ]; then
                log "  Skipping $role for network $prefix (not present)"
                continue
            fi
            container=$(jq -r ".l2_chains[\"$prefix\"].$role.container_name" "$DISCOVERY_JSON")
            service=$(jq -r ".l2_chains[\"$prefix\"].$role.service_name" "$DISCOVERY_JSON")
            log "Extracting $service configuration..."
            copy_container_dir "$container" "/etc/aggkit" "$CONFIG_DIR/$service"
        done
    done

    # ---- aggkit-proxy config ----------------------------------------------
    if [ "$(jq -r '.aggkit_proxy.found // false' "$DISCOVERY_JSON")" = "true" ]; then
        PROXY_CONTAINER=$(jq -r '.aggkit_proxy.container_name' "$DISCOVERY_JSON")
        PROXY_SERVICE=$(jq -r '.aggkit_proxy.service_name' "$DISCOVERY_JSON")
        log "Extracting $PROXY_SERVICE configuration..."
        copy_container_dir "$PROXY_CONTAINER" "/etc/aggkit-proxy" "$CONFIG_DIR/$PROXY_SERVICE"
    fi

    # ---- haproxy config ----------------------------------------------------
    if [ "$(jq -r '.haproxy.found // false' "$DISCOVERY_JSON")" = "true" ]; then
        HAPROXY_CONTAINER=$(jq -r '.haproxy.container_name' "$DISCOVERY_JSON")
        HAPROXY_SERVICE=$(jq -r '.haproxy.service_name' "$DISCOVERY_JSON")
        log "Extracting $HAPROXY_SERVICE configuration..."
        copy_container_file "$HAPROXY_CONTAINER" "/usr/local/etc/haproxy/haproxy.cfg" \
            "$CONFIG_DIR/$HAPROXY_SERVICE/haproxy.cfg"
    fi

    # ---- dev-ui config -----------------------------------------------------
    if [ "$(jq -r '.dev_ui.found // false' "$DISCOVERY_JSON")" = "true" ]; then
        DEV_UI_CONTAINER=$(jq -r '.dev_ui.container_name' "$DISCOVERY_JSON")
        DEV_UI_SERVICE=$(jq -r '.dev_ui.service_name' "$DISCOVERY_JSON")
        log "Extracting $DEV_UI_SERVICE configuration..."
        copy_container_file "$DEV_UI_CONTAINER" "/etc/agglayer-dev-ui/config.json" \
            "$CONFIG_DIR/$DEV_UI_SERVICE/config.json"
    fi

    # ---- network ids (authoritative, straight out of the aggkit configs) ---
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON"); do
        service=$(jq -r ".l2_chains[\"$prefix\"].aggkit.service_name" "$DISCOVERY_JSON")
        l2_service=$(jq -r ".l2_chains[\"$prefix\"].anvil.service_name" "$DISCOVERY_JSON")
        cfg="$CONFIG_DIR/$service/config.toml"
        if [ -f "$cfg" ]; then
            network_id=$(grep -m1 -E '^[[:space:]]*NetworkID[[:space:]]*=' "$cfg" | grep -oE '[0-9]+' | head -1)
            if [ -n "$network_id" ]; then
                CHAINS_META=$(echo "$CHAINS_META" | jq \
                    --arg service "$l2_service" --argjson network_id "$network_id" \
                    'map(if .service == $service then . + {network_id: $network_id} else . end)')
                log "  Network id for $l2_service: $network_id (from $service config.toml)"
            fi
        fi
    done

    # ---- settlement-freeness probe ----------------------------------------
    # agglayer/aggkit internal databases are deliberately NOT captured, so a
    # snapshot taken while certificates exist restores into an inconsistent
    # world (the chains remember bridges the certificate bookkeeping does
    # not). This does not fail the extraction -- the tooling still produces a
    # well-formed bundle -- but it must be recorded loudly.
    SETTLEMENT_FREE="null"
    CERT_HEIGHTS='[]'
    AGGLAYER_READRPC_PORT=$(jq -r '.agglayer.ports["4444"] // empty' "$DISCOVERY_JSON")
    if [ -n "$AGGLAYER_READRPC_PORT" ]; then
        SETTLEMENT_FREE=true
        for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON"); do
            net=$(echo "$CHAINS_META" | jq -r --arg p "$prefix" \
                'map(select(.prefix == $p)) | .[0].network_id // empty')
            [ -z "$net" ] && continue
            header=$(curl -s --max-time 15 "http://127.0.0.1:$AGGLAYER_READRPC_PORT" \
                -X POST -H 'Content-Type: application/json' \
                --data "{\"jsonrpc\":\"2.0\",\"method\":\"interop_getLatestKnownCertificateHeader\",\"params\":[$net],\"id\":1}" \
                2>/dev/null || echo '{}')
            height=$(echo "$header" | jq -r '.result.height // empty')
            status=$(echo "$header" | jq -r '.result.status // empty')
            CERT_HEIGHTS=$(echo "$CERT_HEIGHTS" | jq \
                --argjson network_id "$net" \
                --arg height "${height:-none}" \
                --arg status "${status:-none}" \
                '. + [{network_id: $network_id, latest_known_certificate_height: $height, status: $status}]')
            if [ -n "$height" ]; then
                SETTLEMENT_FREE=false
                log "  WARNING: network $net already has certificates (latest known height $height, status $status)"
            fi
        done
        if [ "$SETTLEMENT_FREE" = "true" ]; then
            log "  ✓ No certificates known to agglayer -- capture is settlement-free"
        else
            log "  ================================================================"
            log "  WARNING: THIS ENCLAVE HAS SETTLEMENT ACTIVITY."
            log "  agglayer/aggkit internal databases are NOT captured, so restoring"
            log "  this snapshot yields chains whose bridge history the certificate"
            log "  bookkeeping cannot account for. Capture from a freshly created,"
            log "  un-bridged enclave for a snapshot that is meant to be used."
            log "  ================================================================"
        fi
    else
        log "  WARNING: agglayer readrpc port not published; settlement-freeness not checked"
    fi

    # ---- metadata ----------------------------------------------------------
    # S9b: make the bundle self-describing about historical states. A dump
    # with historical_states == 0 cannot settle certificates after restore, so
    # S10/S11 can gate on this the same way they gate on settlement_free.
    for idx in $(seq 0 $(( $(echo "$CHAINS_META" | jq 'length') - 1 ))); do
        chain_state_file=$(echo "$CHAINS_META" | jq -r ".[$idx].state_file")
        chain_historical=$(jq -r '.historical_states | if . == null then 0 else length end' \
            "$OUTPUT_DIR/$chain_state_file")
        chain_bytes=$(wc -c < "$OUTPUT_DIR/$chain_state_file")
        CHAINS_META=$(echo "$CHAINS_META" | jq \
            --argjson i "$idx" --argjson hs "$chain_historical" --argjson sz "$chain_bytes" \
            '.[$i] += {historical_states: $hs, state_file_bytes: $sz}')
    done

    jq -n \
        --arg flavor "$FLAVOR" \
        --arg enclave_name "$ENCLAVE_NAME" \
        --arg captured_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --argjson chains "$CHAINS_META" \
        --argjson settlement_free "$SETTLEMENT_FREE" \
        --argjson certificates "$CERT_HEIGHTS" \
        '{flavor: $flavor,
          enclave_name: $enclave_name,
          captured_at: $captured_at,
          capture_method: "anvil_dumpState RPC (live, no container stop)",
          chains: $chains,
          settlement_free: $settlement_free,
          agglayer_certificates: $certificates}' \
        > "$STATE_DIR/state-metadata.json"

    log "State extraction complete (flavor: anvil-aggkit)"
    log "State files:"
    find "$STATE_DIR" -type f | sort | sed 's/^/  /'
    log "Config files:"
    find "$CONFIG_DIR" -type f | sort | sed 's/^/  /'

    exit 0
fi

ENCLAVE_NAME=$(jq -r '.enclave_name' "$DISCOVERY_JSON")
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

# Check if we have L2 chains to process
L2_CHAINS_COUNT=$(jq -r '.l2_chains | length // 0' "$DISCOVERY_JSON" 2>/dev/null || echo "0")
if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    log "L2 chains detected: $L2_CHAINS_COUNT network(s)"
    # Create config directories for each L2 network
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        mkdir -p "$OUTPUT_DIR/config/$prefix"
        log "  Created config directory for L2 network: $prefix"
    done
fi

# ============================================================================
# STEP 1: Extract Lighthouse Checkpoint State (BEFORE stopping)
# ============================================================================

log "Extracting Lighthouse checkpoint state..."

# Get beacon container's beacon API port
BEACON_PORT=$(docker port "$BEACON_CONTAINER" 4000 | cut -d: -f2)

if [ -z "$BEACON_PORT" ]; then
    log "ERROR: Could not find beacon API port"
    exit 1
fi

BEACON_API="http://localhost:$BEACON_PORT"

# Get finalized checkpoint info
log "  Querying finalized checkpoint..."
FINALIZED_DATA=$(curl -s "$BEACON_API/eth/v1/beacon/states/finalized/finality_checkpoints")

if [ -z "$FINALIZED_DATA" ] || echo "$FINALIZED_DATA" | grep -q "error"; then
    log "ERROR: Failed to query finalized checkpoint"
    exit 1
fi

FINALIZED_EPOCH=$(echo "$FINALIZED_DATA" | jq -r '.data.finalized.epoch')
FINALIZED_ROOT=$(echo "$FINALIZED_DATA" | jq -r '.data.finalized.root')

log "  Finalized epoch: $FINALIZED_EPOCH"
log "  Finalized root: $FINALIZED_ROOT"

# Get beacon chain config to determine SLOTS_PER_EPOCH
log "  Querying beacon chain config..."
BEACON_CONFIG=$(curl -s "$BEACON_API/eth/v1/config/spec")
SLOTS_PER_EPOCH=$(echo "$BEACON_CONFIG" | jq -r '.data.SLOTS_PER_EPOCH // "32"')
log "  Slots per epoch: $SLOTS_PER_EPOCH"

# Calculate epoch start slot for Teku compatibility
# Teku requires checkpoints to be from the START of an epoch
EPOCH_START_SLOT=$((FINALIZED_EPOCH * SLOTS_PER_EPOCH))

log "  Calculated epoch start slot: $EPOCH_START_SLOT"

# Get finalized state slot (for comparison)
log "  Querying finalized state slot..."
FINALIZED_HEADER=$(curl -s "$BEACON_API/eth/v1/beacon/headers/finalized")
FINALIZED_SLOT=$(echo "$FINALIZED_HEADER" | jq -r '.data.header.message.slot // .data.slot // "0"')

log "  Finalized slot (actual): $FINALIZED_SLOT"

# Find a non-empty block near epoch boundary to get state_root
# Scan forward from epoch_start_slot within the epoch to find a block
log "  Scanning for non-empty block near epoch boundary (starting from slot $EPOCH_START_SLOT)..."

STATE_ROOT=""
CHECKPOINT_BLOCK_ROOT=""
CHECKPOINT_SLOT=""

# Scan up to SLOTS_PER_EPOCH slots forward from epoch start
for ((offset=0; offset<SLOTS_PER_EPOCH; offset++)); do
    SCAN_SLOT=$((EPOCH_START_SLOT + offset))

    # Query block header at this slot
    HEADER_DATA=$(curl -s "$BEACON_API/eth/v1/beacon/headers/$SCAN_SLOT" 2>/dev/null || echo "")

    if [ -n "$HEADER_DATA" ] && echo "$HEADER_DATA" | jq -e '.data' &>/dev/null; then
        # Extract state_root (not block root!) from the header
        STATE_ROOT=$(echo "$HEADER_DATA" | jq -r '.data.header.message.state_root // empty')
        CHECKPOINT_BLOCK_ROOT=$(echo "$HEADER_DATA" | jq -r '.data.root // empty')
        CHECKPOINT_SLOT="$SCAN_SLOT"

        if [ -n "$STATE_ROOT" ] && [ "$STATE_ROOT" != "null" ]; then
            log "  Found block at slot $CHECKPOINT_SLOT with state root: $STATE_ROOT"
            break
        fi
    fi
done

# Fallback to finalized checkpoint if no block found near epoch boundary
if [ -z "$STATE_ROOT" ] || [ "$STATE_ROOT" = "null" ]; then
    log "  No block found near epoch boundary, using finalized checkpoint"
    FINALIZED_HEADER=$(curl -s "$BEACON_API/eth/v1/beacon/headers/finalized")
    STATE_ROOT=$(echo "$FINALIZED_HEADER" | jq -r '.data.header.message.state_root // empty')
    CHECKPOINT_BLOCK_ROOT="$FINALIZED_ROOT"
    CHECKPOINT_SLOT="$FINALIZED_SLOT"

    if [ -z "$STATE_ROOT" ] || [ "$STATE_ROOT" = "null" ]; then
        log "ERROR: Could not determine state root"
        exit 1
    fi
    log "  Using finalized state root: $STATE_ROOT"
fi

# Download finalized state directly (Lighthouse keeps this available)
# Note: Downloading by state_root doesn't work with Lighthouse as it prunes historical states
log "  Downloading finalized checkpoint state..."
curl -s "$BEACON_API/eth/v2/debug/beacon/states/finalized" \
    -H "Accept: application/octet-stream" \
    -o "$OUTPUT_DIR/datadirs/checkpoint_state.ssz"

if [ ! -f "$OUTPUT_DIR/datadirs/checkpoint_state.ssz" ]; then
    log "ERROR: Failed to download checkpoint state"
    exit 1
fi

# Download checkpoint block
log "  Downloading checkpoint block (root: $CHECKPOINT_BLOCK_ROOT)..."
curl -s "$BEACON_API/eth/v2/beacon/blocks/$CHECKPOINT_BLOCK_ROOT" \
    -H "Accept: application/octet-stream" \
    -o "$OUTPUT_DIR/datadirs/checkpoint_block.ssz"

if [ ! -f "$OUTPUT_DIR/datadirs/checkpoint_block.ssz" ]; then
    log "ERROR: Failed to download checkpoint block"
    exit 1
fi

# Update metadata with the actual checkpoint slot we're using
FINALIZED_SLOT="$CHECKPOINT_SLOT"

# Get seconds_per_slot from beacon config
log "  Querying beacon chain config..."
BEACON_CONFIG=$(curl -s "$BEACON_API/eth/v1/config/spec")
SECONDS_PER_SLOT=$(echo "$BEACON_CONFIG" | jq -r '.data.SECONDS_PER_SLOT // "2"')
log "  Seconds per slot: $SECONDS_PER_SLOT"

# Get execution block number from finalized beacon state
log "  Querying execution block number from finalized state..."
EXEC_PAYLOAD_HEADER=$(curl -s "$BEACON_API/eth/v2/beacon/blocks/finalized" | jq -r '.data.message.body.execution_payload.block_number // .data.message.body.execution_payload_header.block_number // "0"')
log "  Execution block number: $EXEC_PAYLOAD_HEADER"

# Save checkpoint metadata with epoch-aligned slot
cat > "$OUTPUT_DIR/datadirs/checkpoint_metadata.json" << EOF
{
    "finalized_epoch": "$FINALIZED_EPOCH",
    "epoch_start_slot": "$EPOCH_START_SLOT",
    "finalized_slot": "$FINALIZED_SLOT",
    "finalized_root": "$FINALIZED_ROOT",
    "execution_block_number": "$EXEC_PAYLOAD_HEADER",
    "snapshot_time": "$(date -u +%s)",
    "seconds_per_slot": "$SECONDS_PER_SLOT"
}
EOF

log "  Checkpoint state extracted: $(du -h "$OUTPUT_DIR/datadirs/checkpoint_state.ssz" | cut -f1)"
log "  Checkpoint block extracted: $(du -h "$OUTPUT_DIR/datadirs/checkpoint_block.ssz" | cut -f1)"

# ============================================================================
# STEP 2: Stop containers gracefully
# ============================================================================

log "Stopping containers gracefully (IMMEDIATELY to prevent state drift)..."

for container in "$GETH_CONTAINER" "$BEACON_CONTAINER" "$VALIDATOR_CONTAINER"; do
    if docker ps -q --filter "name=$container" | grep -q .; then
        log "  Stopping $container..."
        docker stop "$container" --time 5

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
# STEP 2.5: Verify Execution Layer Synchronization
# ============================================================================

log "Verifying execution layer block matches checkpoint..."

# Query geth's latest block from the stopped container's database
# We need to briefly restart geth to query its state
log "  Temporarily starting geth to query block number..."
docker start "$GETH_CONTAINER" > /dev/null 2>&1

# Wait for geth to be queryable
sleep 3

# Get geth's current block
GETH_PORT=$(docker port "$GETH_CONTAINER" 8545 2>/dev/null | cut -d: -f2 || echo "")
if [ -n "$GETH_PORT" ]; then
    GETH_BLOCK_HEX=$(curl -s "http://localhost:$GETH_PORT" \
        -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null \
        | jq -r '.result // "0x0"')

    GETH_BLOCK=$((16#${GETH_BLOCK_HEX#0x}))
    log "  Geth block number: $GETH_BLOCK"
    log "  Checkpoint execution block: $EXEC_PAYLOAD_HEADER"

    BLOCK_DIFF=$((GETH_BLOCK - EXEC_PAYLOAD_HEADER))
    if [ "$BLOCK_DIFF" -gt 0 ]; then
        log "  WARNING: Geth is $BLOCK_DIFF blocks ahead of checkpoint!"
        log "  Attempting to rollback geth to block $EXEC_PAYLOAD_HEADER..."

        # Convert checkpoint block to hex for RPC call
        CHECKPOINT_HEX=$(printf "0x%x" "$EXEC_PAYLOAD_HEADER")

        # Use debug_setHead to rollback geth's chain
        ROLLBACK_RESULT=$(curl -s "http://localhost:$GETH_PORT" \
            -X POST \
            -H "Content-Type: application/json" \
            --data "{\"jsonrpc\":\"2.0\",\"method\":\"debug_setHead\",\"params\":[\"$CHECKPOINT_HEX\"],\"id\":1}" 2>/dev/null)

        log "  Rollback result: $ROLLBACK_RESULT"

        # Verify rollback succeeded
        sleep 2
        GETH_BLOCK_AFTER_HEX=$(curl -s "http://localhost:$GETH_PORT" \
            -X POST \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null \
            | jq -r '.result // "0x0"')

        GETH_BLOCK_AFTER=$((16#${GETH_BLOCK_AFTER_HEX#0x}))
        if [ "$GETH_BLOCK_AFTER" -eq "$EXEC_PAYLOAD_HEADER" ]; then
            log "  ✓ Geth successfully rolled back to block $EXEC_PAYLOAD_HEADER"
            GETH_BLOCK="$GETH_BLOCK_AFTER"
        else
            log "  ERROR: Rollback failed! Geth is at block $GETH_BLOCK_AFTER, expected $EXEC_PAYLOAD_HEADER"
            log "  Continuing anyway - snapshot may have sync issues"
        fi
    elif [ "$BLOCK_DIFF" -lt 0 ]; then
        log "  WARNING: Geth is $((BLOCK_DIFF * -1)) blocks behind checkpoint!"
        log "  This should not happen - checkpoint may be invalid"
    else
        log "  ✓ Geth block matches checkpoint exactly"
    fi
else
    log "  WARNING: Could not query geth block number"
    GETH_BLOCK="unknown"
fi

# Stop geth again
docker stop "$GETH_CONTAINER" --time 5 > /dev/null 2>&1
sleep 2

# Save the actual geth block to metadata
if [ "$GETH_BLOCK" != "unknown" ]; then
    GETH_BLOCK_FOR_JSON="$GETH_BLOCK"
else
    GETH_BLOCK_FOR_JSON="null"
fi

# Update checkpoint metadata with geth block info
cat > "$OUTPUT_DIR/datadirs/checkpoint_metadata.json" << EOF
{
    "finalized_epoch": "$FINALIZED_EPOCH",
    "epoch_start_slot": "$EPOCH_START_SLOT",
    "finalized_slot": "$FINALIZED_SLOT",
    "finalized_root": "$FINALIZED_ROOT",
    "execution_block_number": "$EXEC_PAYLOAD_HEADER",
    "geth_actual_block_number": $GETH_BLOCK_FOR_JSON,
    "block_drift": $((GETH_BLOCK - EXEC_PAYLOAD_HEADER)),
    "snapshot_time": "$(date -u +%s)",
    "seconds_per_slot": "$SECONDS_PER_SLOT"
}
EOF

log "Checkpoint verification complete"

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
# STEP 4: Extract Lighthouse Validator datadir
# ============================================================================

log "Extracting Lighthouse validator datadir..."

VALIDATOR_TAR="$OUTPUT_DIR/datadirs/lighthouse_validator.tar"
mkdir -p "$OUTPUT_DIR/datadirs/validator-data"

# Extract from both locations
log "  Extracting validator keys..."
docker cp "$VALIDATOR_CONTAINER:/root/.lighthouse/custom" "$OUTPUT_DIR/datadirs/validator-data/lighthouse" 2>/dev/null || true

log "  Extracting validator keystore..."
docker cp "$VALIDATOR_CONTAINER:/validator-keys" "$OUTPUT_DIR/datadirs/validator-data/validator-keys" 2>/dev/null || true

# Explicitly extract Teku keys and secrets (may not be included in bulk copy due to permissions)
log "  Extracting Teku-specific keys and secrets..."
docker cp "$VALIDATOR_CONTAINER:/validator-keys/teku-keys" "$OUTPUT_DIR/datadirs/validator-data/validator-keys/teku-keys" 2>/dev/null || log "    WARNING: teku-keys not found"
docker cp "$VALIDATOR_CONTAINER:/validator-keys/teku-secrets" "$OUTPUT_DIR/datadirs/validator-data/validator-keys/teku-secrets" 2>/dev/null || log "    WARNING: teku-secrets not found"

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
VALIDATOR_COUNT=$(find "$OUTPUT_DIR/datadirs/validator-data/validator-keys/keys" -maxdepth 1 -name "0x*" | wc -l)
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
# STEP 6.5: Extract L2 Configurations (op-reth and op-node)
# ============================================================================

if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    log "========================================="
    log "Extracting L2 Configurations"
    log "========================================="

    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        log "Processing L2 network: $prefix"

        # Get container names for this network
        OP_RETH_SEQ=$(jq -r ".l2_chains[\"$prefix\"].op_reth_sequencer.container_name" "$DISCOVERY_JSON")
        OP_NODE_SEQ=$(jq -r ".l2_chains[\"$prefix\"].op_node_sequencer.container_name" "$DISCOVERY_JSON")
        AGGKIT_CONTAINER=$(jq -r ".l2_chains[\"$prefix\"].aggkit.container_name // empty" "$DISCOVERY_JSON")

        log "  Containers:"
        log "    op-reth sequencer: $OP_RETH_SEQ"
        log "    op-node sequencer: $OP_NODE_SEQ"
        if [ -n "$AGGKIT_CONTAINER" ] && [ "$AGGKIT_CONTAINER" != "null" ]; then
            log "    aggkit: $AGGKIT_CONTAINER"
        fi

        # Extract op-node configuration
        log "  Extracting op-node configuration..."

        # Rollup config (critical for op-node) - with timestamp suffix pattern
        ROLLUP_FILE=$(docker exec "$OP_NODE_SEQ" find /network-configs -name "rollup-*.json" | head -1)
        if [ -n "$ROLLUP_FILE" ]; then
            if docker cp "$OP_NODE_SEQ:$ROLLUP_FILE" "$OUTPUT_DIR/config/$prefix/rollup.json"; then
                log "    ✓ rollup.json extracted from $ROLLUP_FILE"
            else
                log "    WARNING: Failed to extract $ROLLUP_FILE"
            fi
        else
            log "    WARNING: rollup-*.json not found"
        fi

        # Genesis file (may be needed) - with timestamp suffix pattern
        GENESIS_FILE=$(docker exec "$OP_NODE_SEQ" find /network-configs -name "genesis-*.json" | head -1)
        if [ -n "$GENESIS_FILE" ]; then
            if docker cp "$OP_NODE_SEQ:$GENESIS_FILE" "$OUTPUT_DIR/config/$prefix/l2-genesis.json"; then
                log "    ✓ l2-genesis.json extracted from $GENESIS_FILE"
            else
                log "    WARNING: Failed to extract $GENESIS_FILE"
            fi
        else
            log "    WARNING: genesis-*.json not found"
        fi

        # L1 genesis (needed by op-node for --rollup.l1-chain-config)
        # Extract from the running op-node container itself (it has the compatible version)
        if docker cp "$OP_NODE_SEQ:/l1/genesis.json" "$OUTPUT_DIR/config/$prefix/l1-genesis.json" 2>/dev/null; then
            log "    ✓ l1-genesis.json extracted from op-node"
        else
            log "    WARNING: Failed to extract L1 genesis.json from op-node"
        fi

        # Extract op-reth configuration
        log "  Extracting op-reth configuration..."

        # Genesis file (op-reth may have its own)
        if [ ! -f "$OUTPUT_DIR/config/$prefix/l2-genesis.json" ]; then
            if docker cp "$OP_RETH_SEQ:/network-configs/genesis.json" "$OUTPUT_DIR/config/$prefix/l2-genesis.json" 2>/dev/null; then
                log "    ✓ l2-genesis.json extracted from op-reth"
            else
                log "    WARNING: l2-genesis.json not found in op-reth"
            fi
        fi

        # JWT secret (shared between op-reth and op-node)
        if docker cp "$OP_RETH_SEQ:/jwt/jwtsecret" "$OUTPUT_DIR/config/$prefix/jwt.hex" 2>/dev/null; then
            log "    ✓ jwt.hex extracted"
        elif docker cp "$OP_NODE_SEQ:/jwt/jwtsecret" "$OUTPUT_DIR/config/$prefix/jwt.hex" 2>/dev/null; then
            log "    ✓ jwt.hex extracted from op-node"
        else
            log "    WARNING: jwt.hex not found"
        fi

        # Extract aggkit configuration if present
        if [ -n "$AGGKIT_CONTAINER" ] && [ "$AGGKIT_CONTAINER" != "null" ]; then
            log "  Extracting aggkit configuration for network $prefix..."

            # Config file
            if docker cp "$AGGKIT_CONTAINER:/etc/aggkit/config.toml" "$OUTPUT_DIR/config/$prefix/aggkit-config.toml" 2>/dev/null; then
                log "    ✓ aggkit-config.toml extracted"
            else
                log "    WARNING: aggkit-config.toml not found"
            fi

            # Keystores
            if docker cp "$AGGKIT_CONTAINER:/etc/aggkit/sequencer.keystore" "$OUTPUT_DIR/config/$prefix/sequencer.keystore" 2>/dev/null; then
                log "    ✓ sequencer.keystore extracted"
            else
                log "    WARNING: sequencer.keystore not found"
            fi

            if docker cp "$AGGKIT_CONTAINER:/etc/aggkit/aggoracle.keystore" "$OUTPUT_DIR/config/$prefix/aggoracle.keystore" 2>/dev/null; then
                log "    ✓ aggoracle.keystore extracted"
            else
                log "    WARNING: aggoracle.keystore not found"
            fi

            if docker cp "$AGGKIT_CONTAINER:/etc/aggkit/sovereignadmin.keystore" "$OUTPUT_DIR/config/$prefix/sovereignadmin.keystore" 2>/dev/null; then
                log "    ✓ sovereignadmin.keystore extracted"
            else
                log "    WARNING: sovereignadmin.keystore not found"
            fi

            docker cp "$AGGKIT_CONTAINER:/etc/aggkit/claimsponsor.keystore" "$OUTPUT_DIR/config/$prefix/claimsponsor.keystore" 2>/dev/null || true

            # L2 config adaptation is now handled by snapshot.sh after extraction
            log "  ✓ aggkit config extracted (will be adapted after all extraction completes)"
        fi

        # Verify critical files exist
        CRITICAL_FILES=(
            "$OUTPUT_DIR/config/$prefix/rollup.json"
            "$OUTPUT_DIR/config/$prefix/jwt.hex"
        )

        MISSING_CRITICAL=0
        for file in "${CRITICAL_FILES[@]}"; do
            if [ ! -f "$file" ]; then
                log "  ERROR: Critical file missing: $(basename "$file")"
                MISSING_CRITICAL=$((MISSING_CRITICAL + 1))
            fi
        done

        if [ $MISSING_CRITICAL -gt 0 ]; then
            log "  WARNING: L2 network $prefix is missing $MISSING_CRITICAL critical file(s)"
            log "  This network may not function properly in the snapshot"
        else
            log "  ✓ L2 network $prefix: all critical files extracted"
        fi

        log "  L2 network $prefix configuration extraction complete"
    done

    log "All L2 configurations extracted"
    log "  Note: L2 datadirs NOT extracted (stateless by design)"
else
    log "Skipping L2 extraction (no L2 networks found)"
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

# Extract genesis.ssz from Kurtosis artifact
log "  Extracting genesis.ssz from Kurtosis artifact..."
kurtosis files download "$ENCLAVE_NAME" el_cl_genesis_data "$OUTPUT_DIR/artifacts/genesis-artifact" 2>/dev/null || log "  WARNING: Could not download el_cl_genesis_data artifact"
if [ -f "$OUTPUT_DIR/artifacts/genesis-artifact/genesis.ssz" ]; then
    cp "$OUTPUT_DIR/artifacts/genesis-artifact/genesis.ssz" "$OUTPUT_DIR/artifacts/genesis.ssz"
    rm -rf "$OUTPUT_DIR/artifacts/genesis-artifact"
    log "  genesis.ssz extracted successfully"
else
    log "  WARNING: genesis.ssz not found in artifact"
fi

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
find "$OUTPUT_DIR/datadirs/" -maxdepth 1 -name "*.tar" -exec ls -lh {} + | awk '{print "  " $9 " (" $5 ")"}'

log "Artifacts:"
find "$OUTPUT_DIR/artifacts" -type f | sed 's/^/  /'

if [ "$AGGLAYER_FOUND" = "true" ]; then
    log "Agglayer config:"
    find "$OUTPUT_DIR/config/agglayer" -type f | sed 's/^/  /'
fi

exit 0
