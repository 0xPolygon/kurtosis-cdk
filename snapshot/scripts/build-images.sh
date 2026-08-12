#!/usr/bin/env bash
#
# Docker Image Builder Script
# Builds Docker images with L1 state baked in
#
# Usage: build-images.sh [--flavor default|anvil-aggkit] <DISCOVERY_JSON> <OUTPUT_DIR> [TAG_SUFFIX]
#

set -euo pipefail

FLAVOR="default"
while [ $# -gt 0 ]; do
    case "$1" in
        --flavor)
            FLAVOR="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 [--flavor default|anvil-aggkit] <DISCOVERY_JSON> <OUTPUT_DIR> [TAG_SUFFIX]" >&2
    exit 1
fi

DISCOVERY_JSON="$1"
OUTPUT_DIR="$2"
TAG_SUFFIX="${3:-}"

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

log "Starting Docker image build"

# Read container info from discovery JSON
if [ ! -f "$DISCOVERY_JSON" ]; then
    log "ERROR: Discovery file not found: $DISCOVERY_JSON"
    exit 1
fi

ENCLAVE_NAME=$(jq -r '.enclave_name' "$DISCOVERY_JSON")

# Generate tag
TIMESTAMP=$(date -u +'%Y%m%d-%H%M%S')
if [ -n "$TAG_SUFFIX" ]; then
    TAG="${ENCLAVE_NAME}-${TIMESTAMP}-${TAG_SUFFIX}"
else
    TAG="${ENCLAVE_NAME}-${TIMESTAMP}"
fi

log "Image tag: $TAG"

# ============================================================================
# Flavor: anvil-aggkit
#
# Every service in this flavor becomes a *self-contained* derived image: the
# original upstream image plus the captured state/config COPYed in, so the
# distributed bundle is nothing but docker-compose.yml + summary.json. There
# are deliberately NO bind mounts and NO volumes -- see snapshot/README.md.
#
# The default (geth/lighthouse) flavor continues below this block, untouched.
# ============================================================================

if [ "$FLAVOR" = "anvil-aggkit" ]; then
    STATE_METADATA="$OUTPUT_DIR/state/state-metadata.json"
    if [ ! -f "$STATE_METADATA" ]; then
        log "ERROR: state metadata not found: $STATE_METADATA"
        log "       (run extract-state.sh --flavor anvil-aggkit first)"
        exit 1
    fi

    # Healthchecks have to run inside images that ship no shell (aggkit is
    # distroless) and no HTTP client (foundry, agglayer and haproxy all lack
    # curl/wget). A single statically linked busybox is COPYed in from this
    # pinned image and invoked explicitly as `/snapshot/busybox <applet>` --
    # busybox is not installed with applet symlinks, so `sh` alone cannot
    # find them.
    BUSYBOX_IMAGE="${SNAPSHOT_BUSYBOX_IMAGE:-busybox:1.36-musl}"

    IMAGE_PREFIX="snapshot-"
    IMAGES_JSON="$OUTPUT_DIR/images/IMAGE_INFO.json"
    mkdir -p "$OUTPUT_DIR/images"
    echo '{}' > "$OUTPUT_DIR/images/.built.json"

    # record_image <compose-service> <built-image-ref> <base-image>
    record_image() {
        local svc="$1" built="$2" base="$3" size
        size=$(docker images --format '{{.Size}}' "$built" | head -1)
        jq --arg svc "$svc" --arg name "$built" --arg base "$base" --arg size "$size" \
            '. + {($svc): {name: $name, base_image: $base, size: $size}}' \
            "$OUTPUT_DIR/images/.built.json" > "$OUTPUT_DIR/images/.built.tmp.json"
        mv "$OUTPUT_DIR/images/.built.tmp.json" "$OUTPUT_DIR/images/.built.json"
        log "  ✓ $built ($size)"
    }

    # ------------------------------------------------------------------
    # derive_anvil_restore_cmd <original-cmd> <baked-state-path>
    #
    # The enclave's anvil command line is captured verbatim in
    # state-metadata.json (block time, --slots-in-an-epoch, --chain-id, the
    # mnemonic, ...). The restore command is that line with the three
    # capture/bootstrap-only flags removed and --load-state appended:
    #
    #   --dump-state <path>   L1 only; the snapshot already holds the dump
    #   --init <path>         L2 only; genesis is superseded by the dump, and
    #                         it is what makes --dump-state impossible (S2/S4b)
    #   --timestamp <value>   L2 only; `$(date +%s)` at enclave-launch time,
    #                         meaningless once real blocks are loaded
    #
    # The result stays a single shell-parsed string (exactly how kurtosis ran
    # it, entrypoint /bin/sh -c) so the quoted mnemonic survives intact.
    # ------------------------------------------------------------------
    derive_anvil_restore_cmd() {
        local cmd="$1" state_path="$2" derived
        derived=$(printf '%s' "$cmd" | sed -E \
            -e 's/--dump-state[[:space:]]+[^[:space:]]+//g' \
            -e 's/--init[[:space:]]+[^[:space:]]+//g' \
            -e 's/--timestamp[[:space:]]+\$\([^)]*\)//g' \
            -e 's/--timestamp[[:space:]]+[0-9]+//g' \
            -e 's/[[:space:]]+/ /g' \
            -e 's/[[:space:]]+$//')
        derived="$derived --load-state $state_path"

        # Fail loudly rather than bake a subtly wrong node. Every one of these
        # has bitten this plan at least once.
        case "$derived" in
            anvil\ *) ;;
            *) log "ERROR: derived anvil command does not start with 'anvil': $derived"; exit 1 ;;
        esac
        local flag
        for flag in --dump-state --init --timestamp; do
            if printf '%s' "$derived" | grep -q -- "$flag"; then
                log "ERROR: derived anvil command still contains $flag: $derived"
                exit 1
            fi
        done
        for flag in --slots-in-an-epoch --chain-id --block-time --load-state --port; do
            if ! printf '%s' "$derived" | grep -q -- "$flag"; then
                log "ERROR: derived anvil command lost $flag: $derived"
                exit 1
            fi
        done
        printf '%s' "$derived"
    }

    # ------------------------------------------------------------------
    # Anvil chains (L1 + every L2)
    #
    # The base image is read from the captured metadata, never hardcoded:
    # foundry v1.4.3 lacks eth_getTransactionBySenderAndNonce, which makes
    # agglayer panic and permanently mark certificates InError (S4b). Pinning
    # a literal tag here would silently reintroduce that in the restored
    # snapshot while the source enclave looked healthy.
    # ------------------------------------------------------------------
    log "Building anvil images (state baked in via --load-state)..."

    while IFS=$'\t' read -r SVC BASE_IMAGE STATE_FILE; do
        [ -n "$SVC" ] || continue
        BUILD_DIR="$OUTPUT_DIR/images/$SVC"
        mkdir -p "$BUILD_DIR"

        if [ ! -f "$OUTPUT_DIR/$STATE_FILE" ]; then
            log "ERROR: state file missing: $OUTPUT_DIR/$STATE_FILE"
            exit 1
        fi

        # S9b: the dump MUST carry historical states. Without them a restored
        # anvil serves blocks/txs/receipts/logs for the whole captured history
        # but only ONE state (the tip), so every eth_call / eth_getCode /
        # eth_getTransactionCount pinned to a pre-snapshot block returns
        # BlockOutOfRangeError -- which killed aggkit at startup and made
        # agglayer panic in settlement_task.rs on every certificate.
        # extract-state.sh already refuses to write such a dump; this is the
        # belt-and-braces check at bake time, because the failure mode it
        # guards against is silent until settlement is attempted.
        HIST_COUNT=$(jq -r '.historical_states | if . == null then 0 else length end' "$OUTPUT_DIR/$STATE_FILE")
        if [ -z "$HIST_COUNT" ] || [ "$HIST_COUNT" = "null" ] || [ "$HIST_COUNT" -eq 0 ]; then
            log "ERROR: $STATE_FILE has no historical_states -- it was captured with"
            log "       anvil_dumpState() instead of anvil_dumpState(true). A bundle built"
            log "       from it cannot settle certificates after restore (S9b). Re-capture."
            exit 1
        fi
        log "  $SVC: $HIST_COUNT historical states, $(du -h "$OUTPUT_DIR/$STATE_FILE" | cut -f1) state file"

        cp "$OUTPUT_DIR/$STATE_FILE" "$BUILD_DIR/state.json"

        ORIG_CMD=$(jq -r --arg svc "$SVC" '.chains[] | select(.service == $svc) | .cmd[0]' "$STATE_METADATA")
        RESTORE_CMD=$(derive_anvil_restore_cmd "$ORIG_CMD" "/snapshot/state.json")
        log "  $SVC: $RESTORE_CMD"

        {
            echo '#!/bin/sh'
            echo '# Generated by snapshot/scripts/build-images.sh (flavor anvil-aggkit).'
            echo '# Derived from the enclave command line recorded in state-metadata.json.'
            echo "exec $RESTORE_CMD"
        } > "$BUILD_DIR/entrypoint.sh"

        cat > "$BUILD_DIR/healthcheck.sh" << 'HC_EOF'
#!/bin/sh
# eth_blockNumber against the local node (cast ships in the foundry image).
exec cast block-number --rpc-url http://127.0.0.1:8545
HC_EOF

        # The foundry image runs as a non-root user. /snapshot must therefore
        # be created explicitly with a traversable mode BEFORE anything is
        # COPYed into it: a `COPY --chmod=0444` that has to create its own
        # parent directory gives the directory that same mode, and a 0444
        # directory is not searchable -- the entrypoint then fails with
        # "cannot open /snapshot/entrypoint.sh: Permission denied".
        # The original USER is read back from the base image so nothing about
        # it is hardcoded here.
        ORIG_USER=$(docker image inspect --format '{{.Config.User}}' "$BASE_IMAGE")
        {
            echo "FROM $BASE_IMAGE"
            echo ""
            echo "# Snapshot state + generated entrypoint. Nothing is mounted at run time."
            echo "USER root"
            echo "RUN mkdir -m 0755 -p /snapshot"
            echo "COPY --chmod=0444 state.json /snapshot/state.json"
            echo "COPY --chmod=0555 entrypoint.sh /snapshot/entrypoint.sh"
            echo "COPY --chmod=0555 healthcheck.sh /snapshot/healthcheck.sh"
            [ -n "$ORIG_USER" ] && echo "USER $ORIG_USER"
            echo ""
            echo 'ENTRYPOINT ["/bin/sh", "/snapshot/entrypoint.sh"]'
        } > "$BUILD_DIR/Dockerfile"

        docker build -q -t "${IMAGE_PREFIX}${SVC}:$TAG" "$BUILD_DIR" > /dev/null
        record_image "$SVC" "${IMAGE_PREFIX}${SVC}:$TAG" "$BASE_IMAGE"
    done < <(jq -r '.chains[] | [.service, .image, .state_file] | @tsv' "$STATE_METADATA")

    # ------------------------------------------------------------------
    # agglayer: original image + config + keystore.
    # /etc/agglayer/{storage,backups} are NOT captured (they are agglayer's
    # own RocksDB, which must start empty on a settlement-free snapshot), but
    # they must exist and be writable or agglayer refuses to boot.
    # ------------------------------------------------------------------
    AGGLAYER_SVC=$(jq -r '.agglayer.service_name' "$DISCOVERY_JSON")
    AGGLAYER_IMAGE=$(jq -r '.agglayer.image' "$DISCOVERY_JSON")
    AGGLAYER_METRICS_PORT_NUM=9092
    log "Building agglayer image..."
    BUILD_DIR="$OUTPUT_DIR/images/$AGGLAYER_SVC"
    mkdir -p "$BUILD_DIR"
    cp "$OUTPUT_DIR/config/agglayer/config.toml" "$BUILD_DIR/"
    cp "$OUTPUT_DIR/config/agglayer/aggregator.keystore" "$BUILD_DIR/"

    cat > "$BUILD_DIR/healthcheck.sh" << HC_EOF
#!/bin/sh
# agglayer's prometheus endpoint answers only once the node is serving.
exec /snapshot/busybox wget -q -O /dev/null "http://127.0.0.1:${AGGLAYER_METRICS_PORT_NUM}/metrics"
HC_EOF

    cat > "$BUILD_DIR/Dockerfile" << DOCKER_EOF
FROM $BUSYBOX_IMAGE AS busybox
FROM $AGGLAYER_IMAGE

# /etc/agglayer/{storage,backups} are not captured by design (they are
# agglayer's own RocksDB, which must start empty on a settlement-free
# snapshot) but must exist. /snapshot is created up front so its mode does
# not inherit from a --chmod COPY.
RUN mkdir -m 0755 -p /snapshot && mkdir -p /etc/agglayer/storage /etc/agglayer/backups

COPY config.toml /etc/agglayer/config.toml
COPY aggregator.keystore /etc/agglayer/aggregator.keystore
COPY --from=busybox /bin/busybox /snapshot/busybox
COPY --chmod=0555 healthcheck.sh /snapshot/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/agglayer"]
DOCKER_EOF

    docker build -q -t "${IMAGE_PREFIX}${AGGLAYER_SVC}:$TAG" "$BUILD_DIR" > /dev/null
    record_image "$AGGLAYER_SVC" "${IMAGE_PREFIX}${AGGLAYER_SVC}:$TAG" "$AGGLAYER_IMAGE"

    # ------------------------------------------------------------------
    # NO RESTORE-TIME CONFIG ADAPTATION (S9b).
    #
    # Every captured config is baked in verbatim. S8 used to repoint aggkit's
    # `rollupCreationBlockNumber` / `RollupCreationBlockL1` at the L1 snapshot
    # block, because a restored `anvil --load-state` carried blocks, txs,
    # receipts and logs for the whole captured history but only ONE state (the
    # tip), so aggkit's `[Validator.LerQuerierConfig]` eth_call at the rollup's
    # creation block died with `BlockOutOfRangeError`.
    #
    # That rewrite was a point-patch on one symptom of a general defect: the
    # SAME limitation made agglayer panic in
    # crates/agglayer-settlement-service/src/settlement_task.rs when it probed
    # its settlement signer's nonce inclusion at the pre-snapshot block holding
    # that wallet's earlier tx -- which no config rewrite could reach, and which
    # meant L2->L1 exits could never settle on a restored bundle.
    #
    # extract-state.sh now captures with `anvil_dumpState(true)`, so the
    # restored chain serves state reads at EVERY captured height. Both symptoms
    # disappear at the source, the configs stay faithful to the enclave, and
    # aggkit reads the rollup's genuine creation-time LER instead of an
    # "equal only while settlement_free" substitute.
    # ------------------------------------------------------------------

    # ------------------------------------------------------------------
    # aggkit x N (+ their -bridge siblings)
    #
    # aggkit-00X and aggkit-00X-bridge ship identical config.tomls and differ
    # only in --components, but each gets its own image so the two stay
    # independently pullable/pinnable (S7).
    # ------------------------------------------------------------------
    log "Building aggkit images..."
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON"); do
        NETWORK_ID=$(jq -r --arg p "$prefix" '.chains[] | select(.prefix == $p) | .network_id' "$STATE_METADATA")

        for role in aggkit aggkit_bridge; do
            SVC=$(jq -r --arg p "$prefix" --arg r "$role" '.l2_chains[$p][$r].service_name' "$DISCOVERY_JSON")
            BASE_IMAGE=$(jq -r --arg p "$prefix" --arg r "$role" '.l2_chains[$p][$r].image' "$DISCOVERY_JSON")
            BUILD_DIR="$OUTPUT_DIR/images/$SVC"
            mkdir -p "$BUILD_DIR"
            cp "$OUTPUT_DIR/config/$SVC/config.toml" "$BUILD_DIR/"
            cp "$OUTPUT_DIR/config/$SVC"/*.keystore "$BUILD_DIR/"
            # Baked verbatim -- see the "NO RESTORE-TIME CONFIG ADAPTATION"
            # note above (S9b).

            if [ "$role" = "aggkit_bridge" ]; then
                # The bar S9/dev-ui hold: is_synced AND is_active on BOTH
                # l1_info and l2_info, hence the >= 2 occurrences.
                cat > "$BUILD_DIR/healthcheck.sh" << HC_EOF
#!/bin/sh
BB=/snapshot/busybox
n=\$(\$BB wget -q -O - "http://127.0.0.1:5577/bridge/v1/sync-status?network_id=${NETWORK_ID}" \\
      | \$BB grep -o '"is_synced":true,"is_active":true' | \$BB wc -l)
[ "\$n" -ge 2 ]
HC_EOF
            else
                cat > "$BUILD_DIR/healthcheck.sh" << 'HC_EOF'
#!/bin/sh
# aggsender/aggoracle/autoclaim expose no REST surface; the pprof server
# (ProfilingEnabled = true in the captured config) is the only HTTP endpoint
# that proves the process finished booting.
exec /snapshot/busybox wget -q -O /dev/null http://127.0.0.1:6060/debug/pprof/
HC_EOF
            fi

            {
                echo "FROM $BUSYBOX_IMAGE AS busybox"
                echo "FROM $BASE_IMAGE"
                echo ""
                echo "COPY config.toml /etc/aggkit/config.toml"
                for ks in "$BUILD_DIR"/*.keystore; do
                    echo "COPY $(basename "$ks") /etc/aggkit/$(basename "$ks")"
                done
                echo "# aggkit ships no shell, so no RUN layer is possible here: /snapshot"
                echo "# gets its 0755 mode from this first, plain (non---chmod) COPY."
                echo "COPY --from=busybox /bin/busybox /snapshot/busybox"
                echo "COPY --chmod=0555 healthcheck.sh /snapshot/healthcheck.sh"
                echo ""
                echo 'ENTRYPOINT ["/usr/local/bin/aggkit"]'
            } > "$BUILD_DIR/Dockerfile"

            docker build -q -t "${IMAGE_PREFIX}${SVC}:$TAG" "$BUILD_DIR" > /dev/null
            record_image "$SVC" "${IMAGE_PREFIX}${SVC}:$TAG" "$BASE_IMAGE"
        done
    done

    # ------------------------------------------------------------------
    # aggkit-proxy (--components=proxy,tracker)
    # ------------------------------------------------------------------
    PROXY_SVC=$(jq -r '.aggkit_proxy.service_name' "$DISCOVERY_JSON")
    PROXY_IMAGE=$(jq -r '.aggkit_proxy.image' "$DISCOVERY_JSON")
    ALL_NETWORK_IDS=$(jq -r '[.chains[].network_id] | join(" ")' "$STATE_METADATA")
    log "Building aggkit-proxy image (networks: $ALL_NETWORK_IDS)..."
    BUILD_DIR="$OUTPUT_DIR/images/$PROXY_SVC"
    mkdir -p "$BUILD_DIR"
    cp "$OUTPUT_DIR/config/$PROXY_SVC/config.toml" "$BUILD_DIR/"

    cat > "$BUILD_DIR/healthcheck.sh" << HC_EOF
#!/bin/sh
BB=/snapshot/busybox
for nid in ${ALL_NETWORK_IDS}; do
    n=\$(\$BB wget -q -O - "http://127.0.0.1:8080/bridge/v1/sync-status?network_id=\$nid" \\
          | \$BB grep -o '"is_synced":true,"is_active":true' | \$BB wc -l) || exit 1
    [ "\$n" -ge 2 ] || exit 1
done
exit 0
HC_EOF

    cat > "$BUILD_DIR/Dockerfile" << DOCKER_EOF
FROM $BUSYBOX_IMAGE AS busybox
FROM $PROXY_IMAGE

COPY config.toml /etc/aggkit-proxy/config.toml
COPY --from=busybox /bin/busybox /snapshot/busybox
COPY --chmod=0555 healthcheck.sh /snapshot/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/aggkit-proxy"]
DOCKER_EOF

    docker build -q -t "${IMAGE_PREFIX}${PROXY_SVC}:$TAG" "$BUILD_DIR" > /dev/null
    record_image "$PROXY_SVC" "${IMAGE_PREFIX}${PROXY_SVC}:$TAG" "$PROXY_IMAGE"

    # ------------------------------------------------------------------
    # haproxy (the single CORS origin dev-ui CI talks to)
    # ------------------------------------------------------------------
    HAPROXY_SVC=$(jq -r '.haproxy.service_name' "$DISCOVERY_JSON")
    HAPROXY_IMAGE=$(jq -r '.haproxy.image' "$DISCOVERY_JSON")
    FIRST_L2_NETWORK_ID=$(jq -r '[.chains[] | select(.role == "l2") | .network_id] | first' "$STATE_METADATA")
    log "Building haproxy image..."
    BUILD_DIR="$OUTPUT_DIR/images/$HAPROXY_SVC"
    mkdir -p "$BUILD_DIR"
    cp "$OUTPUT_DIR/config/$HAPROXY_SVC/haproxy.cfg" "$BUILD_DIR/"

    cat > "$BUILD_DIR/healthcheck.sh" << HC_EOF
#!/bin/sh
# Two real routes must answer 200 through the proxy: the aggkit REST route
# dev-ui's bridge suite uses, and the default backend (the dev-ui itself).
# The JSON-RPC routes are POST-only and cannot be probed with busybox wget.
BB=/snapshot/busybox
\$BB wget -q -O /dev/null "http://127.0.0.1:80/aggkitapi/bridge/v1/sync-status?network_id=${FIRST_L2_NETWORK_ID}" || exit 1
\$BB wget -q -O /dev/null "http://127.0.0.1:80/" || exit 1
exit 0
HC_EOF

    cat > "$BUILD_DIR/Dockerfile" << DOCKER_EOF
FROM $BUSYBOX_IMAGE AS busybox
FROM $HAPROXY_IMAGE

COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
COPY --from=busybox /bin/busybox /snapshot/busybox
COPY --chmod=0555 healthcheck.sh /snapshot/healthcheck.sh
DOCKER_EOF

    docker build -q -t "${IMAGE_PREFIX}${HAPROXY_SVC}:$TAG" "$BUILD_DIR" > /dev/null
    record_image "$HAPROXY_SVC" "${IMAGE_PREFIX}${HAPROXY_SVC}:$TAG" "$HAPROXY_IMAGE"

    # ------------------------------------------------------------------
    # dev-ui: the pinned published GHCR image + its runtime config.json
    # (contract: dev-ui docs/docker.md -- /etc/agglayer-dev-ui/config.json).
    # ------------------------------------------------------------------
    DEVUI_SVC=$(jq -r '.dev_ui.service_name' "$DISCOVERY_JSON")
    DEVUI_IMAGE=$(jq -r '.dev_ui.image' "$DISCOVERY_JSON")
    log "Building dev-ui image..."
    BUILD_DIR="$OUTPUT_DIR/images/$DEVUI_SVC"
    mkdir -p "$BUILD_DIR"
    cp "$OUTPUT_DIR/config/$DEVUI_SVC/config.json" "$BUILD_DIR/"

    cat > "$BUILD_DIR/healthcheck.sh" << 'HC_EOF'
#!/bin/sh
exec wget -q -O /dev/null http://127.0.0.1:80/
HC_EOF

    cat > "$BUILD_DIR/Dockerfile" << DOCKER_EOF
FROM $DEVUI_IMAGE

RUN mkdir -m 0755 -p /snapshot
COPY config.json /etc/agglayer-dev-ui/config.json
COPY --chmod=0555 healthcheck.sh /snapshot/healthcheck.sh
DOCKER_EOF

    docker build -q -t "${IMAGE_PREFIX}${DEVUI_SVC}:$TAG" "$BUILD_DIR" > /dev/null
    record_image "$DEVUI_SVC" "${IMAGE_PREFIX}${DEVUI_SVC}:$TAG" "$DEVUI_IMAGE"

    # ------------------------------------------------------------------
    # Image metadata
    # ------------------------------------------------------------------
    jq -n \
        --arg flavor "$FLAVOR" \
        --arg tag "$TAG" \
        --arg prefix "$IMAGE_PREFIX" \
        --arg busybox "$BUSYBOX_IMAGE" \
        --arg ts "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --slurpfile images "$OUTPUT_DIR/images/.built.json" \
        '{
            flavor: $flavor,
            tag: $tag,
            image_prefix: $prefix,
            busybox_image: $busybox,
            timestamp: $ts,
            self_contained: true,
            images: $images[0]
        }' > "$IMAGES_JSON"

    rm -f "$OUTPUT_DIR/images/.built.json"
    echo "$TAG" > "$OUTPUT_DIR/images/.tag"

    log "Image metadata saved: $IMAGES_JSON"
    log "Built $(jq -r '.images | length' "$IMAGES_JSON") self-contained images with tag: $TAG"

    exit 0
fi

GETH_IMAGE=$(jq -r '.geth.image' "$DISCOVERY_JSON")
BEACON_IMAGE=$(jq -r '.beacon.image' "$DISCOVERY_JSON")
VALIDATOR_IMAGE=$(jq -r '.validator.image' "$DISCOVERY_JSON")

# Create images directory
mkdir -p "$OUTPUT_DIR/images"/{geth,beacon,validator}

# ============================================================================
# Build Geth Image
# ============================================================================

log "Building Geth execution layer image..."

GETH_BUILD_DIR="$OUTPUT_DIR/images/geth"

# Copy datadir tarball
cp "$OUTPUT_DIR/datadirs/geth.tar" "$GETH_BUILD_DIR/"

# Copy JWT secret if available
if [ -f "$OUTPUT_DIR/artifacts/jwt.hex" ]; then
    cp "$OUTPUT_DIR/artifacts/jwt.hex" "$GETH_BUILD_DIR/jwtsecret"
else
    # Create a dummy JWT if not found (for testing)
    echo "0x0000000000000000000000000000000000000000000000000000000000000000" > "$GETH_BUILD_DIR/jwtsecret"
fi

# Create Dockerfile
cat > "$GETH_BUILD_DIR/Dockerfile" << 'EOF'
FROM ethereum/client-go:v1.16.8

# Copy geth datadir
COPY geth.tar /tmp/geth.tar

# Copy JWT secret
COPY jwtsecret /tmp/jwtsecret

# Extract datadir and setup JWT
RUN mkdir -p /data/geth /jwt && \
    cd /data/geth && \
    tar -xzf /tmp/geth.tar && \
    mv geth-data execution-data && \
    rm /tmp/geth.tar && \
    mv /tmp/jwtsecret /jwt/jwtsecret && \
    chmod 644 /jwt/jwtsecret

# Set working directory
WORKDIR /data/geth

# Ensure data is accessible
RUN chmod -R 755 /data/geth

# Default command (will be overridden by docker-compose)
CMD ["geth"]
EOF

log "  Building snapshot-geth:$TAG..."
docker build -t "snapshot-geth:$TAG" "$GETH_BUILD_DIR"

if docker images -q "snapshot-geth:$TAG" &> /dev/null; then
    log "  Geth image built successfully"
    docker tag "snapshot-geth:$TAG" "snapshot-geth:latest"
else
    log "ERROR: Failed to build Geth image"
    exit 1
fi

# ============================================================================
# Build Lighthouse Beacon Image
# ============================================================================

log "Building Lighthouse beacon node image..."

BEACON_BUILD_DIR="$OUTPUT_DIR/images/beacon"

# Copy checkpoint SSZ files
cp "$OUTPUT_DIR/datadirs/checkpoint_state.ssz" "$BEACON_BUILD_DIR/"
cp "$OUTPUT_DIR/datadirs/checkpoint_block.ssz" "$BEACON_BUILD_DIR/"
cp "$OUTPUT_DIR/datadirs/checkpoint_metadata.json" "$BEACON_BUILD_DIR/"

# Copy artifacts if available (create empty files if missing to avoid Docker build errors)
if [ -f "$OUTPUT_DIR/artifacts/chain-spec.yaml" ]; then
    cp "$OUTPUT_DIR/artifacts/chain-spec.yaml" "$BEACON_BUILD_DIR/"
else
    touch "$BEACON_BUILD_DIR/chain-spec.yaml"
fi

if [ -f "$OUTPUT_DIR/artifacts/jwt.hex" ]; then
    cp "$OUTPUT_DIR/artifacts/jwt.hex" "$BEACON_BUILD_DIR/"
else
    touch "$BEACON_BUILD_DIR/jwt.hex"
fi

# Copy genesis.ssz if available
if [ -f "$OUTPUT_DIR/artifacts/genesis.ssz" ]; then
    cp "$OUTPUT_DIR/artifacts/genesis.ssz" "$BEACON_BUILD_DIR/"
else
    log "  WARNING: genesis.ssz not found, Teku may fail to start"
    touch "$BEACON_BUILD_DIR/genesis.ssz"
fi

# Create Teku-compatible spec.yaml from Lighthouse chain-spec.yaml
log "  Generating Teku-compatible spec.yaml..."
if [ -f "$OUTPUT_DIR/artifacts/chain-spec.yaml" ]; then
    # Extract key values from the Lighthouse config
    PRESET_BASE=$(grep "^PRESET_BASE:" "$OUTPUT_DIR/artifacts/chain-spec.yaml" | awk '{print $2}' | tr -d "'\"")
    MIN_GENESIS_TIME=$(grep "^MIN_GENESIS_TIME:" "$OUTPUT_DIR/artifacts/chain-spec.yaml" | awk '{print $2}')
    GENESIS_FORK_VERSION=$(grep "^GENESIS_FORK_VERSION:" "$OUTPUT_DIR/artifacts/chain-spec.yaml" | awk '{print $2}')
    SECONDS_PER_SLOT_VALUE=$(grep "^SECONDS_PER_SLOT:" "$OUTPUT_DIR/artifacts/chain-spec.yaml" | awk '{print $2}')

    # Extract fork epochs from chain-spec.yaml (use far future as default if not present)
    FAR_FUTURE=18446744073709551615
    ELECTRA_FORK_EPOCH_VALUE=$(grep "^ELECTRA_FORK_EPOCH:" "$OUTPUT_DIR/artifacts/chain-spec.yaml" | awk '{print $2}')
    ELECTRA_FORK_EPOCH_VALUE=${ELECTRA_FORK_EPOCH_VALUE:-$FAR_FUTURE}
    FULU_FORK_EPOCH_VALUE=$(grep "^FULU_FORK_EPOCH:" "$OUTPUT_DIR/artifacts/chain-spec.yaml" | awk '{print $2}')
    FULU_FORK_EPOCH_VALUE=${FULU_FORK_EPOCH_VALUE:-$FAR_FUTURE}
    FULU_FORK_VERSION_VALUE=$(grep "^FULU_FORK_VERSION:" "$OUTPUT_DIR/artifacts/chain-spec.yaml" | awk '{print $2}')
    FULU_FORK_VERSION_VALUE=${FULU_FORK_VERSION_VALUE:-0x70000038}

    log "  Fork epochs from chain-spec: ELECTRA=$ELECTRA_FORK_EPOCH_VALUE, FULU=$FULU_FORK_EPOCH_VALUE"

    # Create minimal consensus-spec format config for Teku
    cat > "$BEACON_BUILD_DIR/spec.yaml" << SPECEOF
# Teku consensus-spec format config
PRESET_BASE: '${PRESET_BASE:-minimal}'

# Network identity
CONFIG_NAME: 'kurtosis-cdk-devnet'

# Genesis
MIN_GENESIS_ACTIVE_VALIDATOR_COUNT: 128
MIN_GENESIS_TIME: ${MIN_GENESIS_TIME:-1578009600}
GENESIS_FORK_VERSION: ${GENESIS_FORK_VERSION:-0x10000038}
GENESIS_DELAY: 10

# Forking
ALTAIR_FORK_VERSION: 0x20000038
ALTAIR_FORK_EPOCH: 0
BELLATRIX_FORK_VERSION: 0x30000038
BELLATRIX_FORK_EPOCH: 0
CAPELLA_FORK_VERSION: 0x40000038
CAPELLA_FORK_EPOCH: 0
DENEB_FORK_VERSION: 0x50000038
DENEB_FORK_EPOCH: 0
ELECTRA_FORK_VERSION: 0x60000038
ELECTRA_FORK_EPOCH: ${ELECTRA_FORK_EPOCH_VALUE}
FULU_FORK_VERSION: ${FULU_FORK_VERSION_VALUE}
FULU_FORK_EPOCH: ${FULU_FORK_EPOCH_VALUE}

# Time parameters (extracted from chain-spec.yaml, not hardcoded)
SECONDS_PER_SLOT: ${SECONDS_PER_SLOT_VALUE:-12}
SLOTS_PER_EPOCH: 8
MIN_VALIDATOR_WITHDRAWABILITY_DELAY: 256
SHARD_COMMITTEE_PERIOD: 256
MIN_EPOCHS_TO_INACTIVITY_PENALTY: 4

# Ethereum proof of stake parameters
INACTIVITY_SCORE_BIAS: 4
INACTIVITY_SCORE_RECOVERY_RATE: 16
EJECTION_BALANCE: 16000000000
MIN_PER_EPOCH_CHURN_LIMIT: 4
CHURN_LIMIT_QUOTIENT: 65536

# Transition
TERMINAL_TOTAL_DIFFICULTY: 0
TERMINAL_BLOCK_HASH: 0x0000000000000000000000000000000000000000000000000000000000000000
TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH: 18446744073709551615

# Deposit contract
DEPOSIT_CHAIN_ID: 271828
DEPOSIT_NETWORK_ID: 271828
DEPOSIT_CONTRACT_ADDRESS: 0x00000000219ab540356cbb839cbe05303d7705fa

# Networking (required by Teku for custom networks)
GOSSIP_MAX_SIZE: 10485760
MAX_CHUNK_SIZE: 10485760
MAX_REQUEST_BLOCKS: 1024
MIN_EPOCHS_FOR_BLOCK_REQUESTS: 33024
ATTESTATION_PROPAGATION_SLOT_RANGE: 32
SECONDS_PER_ETH1_BLOCK: 14
ATTESTATION_SUBNET_PREFIX_BITS: 6
ATTESTATION_SUBNET_EXTRA_BITS: 0
ATTESTATION_SUBNET_COUNT: 64
SUBNETS_PER_NODE: 2
RESP_TIMEOUT: 10
TTFB_TIMEOUT: 5
MAXIMUM_GOSSIP_CLOCK_DISPARITY: 500
ETH1_FOLLOW_DISTANCE: 2048
EPOCHS_PER_SUBNET_SUBSCRIPTION: 256
MESSAGE_DOMAIN_VALID_SNAPPY: 0x01000000
MESSAGE_DOMAIN_INVALID_SNAPPY: 0x00000000

# Deneb/Blob parameters
MAX_REQUEST_BLOB_SIDECARS: 768
MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS: 4096
MAX_REQUEST_BLOCKS_DENEB: 128
MAX_BLOBS_PER_BLOCK: 6
BLOB_SIDECAR_SUBNET_COUNT: 6
MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT: 8

# Electra parameters (EIP-7691: blob throughput, EIP-7251: validator churn)
MAX_BLOBS_PER_BLOCK_ELECTRA: 9
TARGET_BLOBS_PER_BLOCK_ELECTRA: 6
BLOB_SIDECAR_SUBNET_COUNT_ELECTRA: 9
MAX_REQUEST_BLOB_SIDECARS_ELECTRA: 1152
MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA: 128000000000
SPECEOF
else
    log "  WARNING: chain-spec.yaml not found, using default spec.yaml"
    echo "PRESET_BASE: 'minimal'" > "$BEACON_BUILD_DIR/spec.yaml"
fi

# Create genesis time patcher Java code
cat > "$BEACON_BUILD_DIR/GenesisTimePatcher.java" << 'PATCHER_JAVA_EOF'
import tech.pegasys.teku.spec.Spec;
import tech.pegasys.teku.spec.SpecFactory;
import tech.pegasys.teku.spec.datastructures.state.beaconstate.BeaconState;
import tech.pegasys.teku.infrastructure.unsigned.UInt64;
import org.apache.tuweni.bytes.Bytes;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class GenesisTimePatcher {
    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            System.err.println("Usage: GenesisTimePatcher <spec_yaml> <input_ssz> <new_genesis_time>");
            System.exit(1);
        }

        String specYaml = args[0];
        Path inputFile = Paths.get(args[1]);
        UInt64 newGenesisTime = UInt64.valueOf(args[2]);

        System.out.println("Loading spec from: " + specYaml);
        Spec spec = SpecFactory.create(specYaml);

        System.out.println("Loading checkpoint state from: " + inputFile);
        byte[] sszData = Files.readAllBytes(inputFile);
        Bytes sszBytes = Bytes.wrap(sszData);
        BeaconState originalState = spec.deserializeBeaconState(sszBytes);

        System.out.println("Original genesis_time: " + originalState.getGenesisTime());
        System.out.println("New genesis_time: " + newGenesisTime);

        // Only patch genesis_time, NOT slot (to avoid "empty slot" errors)
        BeaconState patchedState = originalState.updated(state ->
            state.setGenesisTime(newGenesisTime)
        );

        // Verify the change
        if (!patchedState.getGenesisTime().equals(newGenesisTime)) {
            throw new RuntimeException("Failed to update genesis_time");
        }

        System.out.println("Patched genesis_time: " + patchedState.getGenesisTime());

        // Serialize back to SSZ
        byte[] patchedSsz = patchedState.sszSerialize().toArrayUnsafe();

        // Write to temporary file first
        Path tempFile = Paths.get(inputFile.toString() + ".tmp");
        Files.write(tempFile, patchedSsz);

        // Atomic rename to replace original
        Files.move(tempFile, inputFile, java.nio.file.StandardCopyOption.REPLACE_EXISTING);

        System.out.println("Successfully patched checkpoint state");

        // Verify round-trip
        byte[] verifyData = Files.readAllBytes(inputFile);
        Bytes verifyBytes = Bytes.wrap(verifyData);
        BeaconState verifiedState = spec.deserializeBeaconState(verifyBytes);

        if (!verifiedState.getGenesisTime().equals(newGenesisTime)) {
            throw new RuntimeException("Round-trip verification failed");
        }

        System.out.println("Round-trip verification passed");
    }
}
PATCHER_JAVA_EOF

# Create entrypoint script for Teku beacon node
cat > "$BEACON_BUILD_DIR/beacon-entrypoint.sh" << 'ENTRYPOINT_EOF'
#!/bin/bash
set -e

echo "Beacon entrypoint: Starting Teku with checkpoint sync"

# Clear any existing Teku database to avoid genesis time mismatch issues
# The beacon database was created with a different genesis time on previous runs
if [ -d "/data/teku/beacon" ]; then
    echo "Clearing existing Teku database to avoid genesis time conflicts..."
    rm -rf /data/teku/beacon
fi

# Read checkpoint metadata
SNAPSHOT_TIME=$(jq -r '.snapshot_time' /checkpoint/checkpoint_metadata.json)
FINALIZED_EPOCH=$(jq -r '.finalized_epoch' /checkpoint/checkpoint_metadata.json)
EPOCH_START_SLOT=$(jq -r '.epoch_start_slot // "0"' /checkpoint/checkpoint_metadata.json)
FINALIZED_SLOT=$(jq -r '.finalized_slot // "0"' /checkpoint/checkpoint_metadata.json)
NOW=$(date +%s)
TIME_GAP=$((NOW - SNAPSHOT_TIME))

echo "Snapshot was taken at: $(date -d @$SNAPSHOT_TIME -u)"
echo "Current time: $(date -d @$NOW -u)"
echo "Time gap: $TIME_GAP seconds ($((TIME_GAP / 3600)) hours)"
echo "Checkpoint finalized epoch: $FINALIZED_EPOCH"
echo "Checkpoint epoch start slot: $EPOCH_START_SLOT"
echo "Checkpoint finalized slot (actual): $FINALIZED_SLOT"
echo ""

# EXPERIMENTAL: Skip genesis time patching to preserve checkpoint integrity
# Patching breaks Teku's checkpoint validation - "initial state is too recent" error
# Trade-off: Snapshots must be run within ~1 hour of creation
SKIP_GENESIS_PATCHING=${SKIP_GENESIS_PATCHING:-false}

if [ "$SKIP_GENESIS_PATCHING" = "true" ]; then
    echo "Skipping genesis time patching (SKIP_GENESIS_PATCHING=true)"
    echo "Using original checkpoint state without modifications"
elif [ "$EPOCH_START_SLOT" != "0" ] && [ "$EPOCH_START_SLOT" != "null" ] && [ -n "$EPOCH_START_SLOT" ]; then
    echo "Patching checkpoint genesis time (epoch-aligned)..."

    # Extract SECONDS_PER_SLOT from config files (try spec.yaml first, fall back to config.yaml)
    # Use exact match to avoid picking up SECONDS_PER_ETH1_BLOCK
    if [ -f /network-configs/spec.yaml ]; then
        SECONDS_PER_SLOT=$(grep "^SECONDS_PER_SLOT:" /network-configs/spec.yaml | awk '{print $2}')
    fi

    if [ -z "$SECONDS_PER_SLOT" ] && [ -f /network-configs/config.yaml ]; then
        SECONDS_PER_SLOT=$(grep "^SECONDS_PER_SLOT:" /network-configs/config.yaml | awk '{print $2}')
    fi

    if [ -n "$SECONDS_PER_SLOT" ]; then
        # Genesis time calculation with increased slack to bypass "too recent" errors
        # target_slot = finalized_slot + 3*SLOTS_PER_EPOCH
        # new_genesis_time = now - target_slot * SECONDS_PER_SLOT - 30
        # This puts current_slot about 4 epochs ahead of finalized_slot

        # Extract SLOTS_PER_EPOCH from config
        SLOTS_PER_EPOCH=32  # Default
        if [ -f /network-configs/spec.yaml ]; then
            SLOTS_PER_EPOCH_FROM_CONFIG=$(grep "^SLOTS_PER_EPOCH:" /network-configs/spec.yaml | awk '{print $2}')
            if [ -n "$SLOTS_PER_EPOCH_FROM_CONFIG" ]; then
                SLOTS_PER_EPOCH="$SLOTS_PER_EPOCH_FROM_CONFIG"
            fi
        fi

        TARGET_SLOT=$((FINALIZED_SLOT + 3 * SLOTS_PER_EPOCH))
        NEW_GENESIS_TIME=$((NOW - (TARGET_SLOT * SECONDS_PER_SLOT) - 30))

        CALCULATED_CURRENT_SLOT=$(( (NOW - NEW_GENESIS_TIME) / SECONDS_PER_SLOT ))

        echo "  Snapshot time: $SNAPSHOT_TIME"
        echo "  Current time: $NOW"
        echo "  Elapsed time since snapshot: $((NOW - SNAPSHOT_TIME)) seconds"
        echo "  Finalized slot: $FINALIZED_SLOT"
        echo "  SLOTS_PER_EPOCH: $SLOTS_PER_EPOCH"
        echo "  Target slot (finalized + 3*SLOTS_PER_EPOCH): $TARGET_SLOT"
        echo "  Seconds per slot: $SECONDS_PER_SLOT"
        echo "  Calculated new genesis_time: $NEW_GENESIS_TIME"
        echo "  Current slot after patching: $CALCULATED_CURRENT_SLOT"
        echo "  Slots ahead of finalized: $((CALCULATED_CURRENT_SLOT - FINALIZED_SLOT))"

        # Patcher is pre-compiled at build time for faster and more consistent runtime

        # Run patcher on checkpoint state
        echo "  Patching checkpoint_state.ssz..."
        java -cp '/opt/teku/lib/*:/patcher' GenesisTimePatcher \
            /network-configs/spec.yaml \
            /checkpoint/checkpoint_state.ssz \
            $NEW_GENESIS_TIME

        # Also patch genesis.ssz if it exists
        if [ -f /network-configs/genesis.ssz ]; then
            echo "  Patching genesis.ssz..."
            java -cp '/opt/teku/lib/*:/patcher' GenesisTimePatcher \
                /network-configs/spec.yaml \
                /network-configs/genesis.ssz \
                $NEW_GENESIS_TIME
        fi

        echo "  Genesis time patching complete"
    else
        echo "  WARNING: Could not determine SECONDS_PER_SLOT, skipping patching"
    fi
else
    echo "  WARNING: Could not determine checkpoint slot, skipping genesis time patching"
fi

echo ""
echo "Starting Teku with checkpoint state..."

# Start Teku beacon node with checkpoint state
# --ignore-weak-subjectivity-period-enabled allows loading checkpoints with time gaps
# --rest-api-host-allowlist=* allows validator to connect from other docker containers
exec teku \
    --data-path=/data/teku \
    --network=/network-configs/spec.yaml \
    --initial-state=/checkpoint/checkpoint_state.ssz \
    --ee-endpoint=http://geth:8551 \
    --ee-jwt-secret-file=/jwt/jwtsecret \
    --rest-api-enabled=true \
    --rest-api-interface=0.0.0.0 \
    --rest-api-port=4000 \
    --rest-api-host-allowlist=* \
    --p2p-enabled=false \
    --p2p-discovery-enabled=false \
    --p2p-peer-lower-bound=0 \
    --ignore-weak-subjectivity-period-enabled=true \
    --logging=INFO
ENTRYPOINT_EOF

# Create Dockerfile for Teku beacon node
cat > "$BEACON_BUILD_DIR/Dockerfile" << 'EOF'
FROM consensys/teku:26.2.0

# Install curl for healthcheck, jq for JSON parsing
USER root
RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*

# Copy checkpoint files (checkpoint_state.ssz will be patched at runtime)
COPY checkpoint_state.ssz /checkpoint/checkpoint_state.ssz
COPY checkpoint_block.ssz /checkpoint/checkpoint_block.ssz
COPY checkpoint_metadata.json /checkpoint/checkpoint_metadata.json

# Copy artifacts (may be empty files if not available)
COPY chain-spec.yaml /tmp/chain-spec.yaml
COPY jwt.hex /tmp/jwt.hex
COPY genesis.ssz /tmp/genesis.ssz
COPY spec.yaml /tmp/spec.yaml

# Copy and compile genesis time patcher at build time to eliminate runtime compilation variance
RUN mkdir -p /patcher
COPY GenesisTimePatcher.java /patcher/GenesisTimePatcher.java
RUN javac -cp '/opt/teku/lib/*' /patcher/GenesisTimePatcher.java -d /patcher/

# Copy entrypoint script
COPY beacon-entrypoint.sh /usr/local/bin/beacon-entrypoint.sh
RUN chmod +x /usr/local/bin/beacon-entrypoint.sh

# Setup testnet directory and JWT
RUN mkdir -p /network-configs /jwt && \
    if [ -s /tmp/chain-spec.yaml ]; then \
        cp /tmp/chain-spec.yaml /network-configs/config.yaml; \
    fi && \
    if [ -s /tmp/jwt.hex ]; then \
        cp /tmp/jwt.hex /jwt/jwtsecret; \
    fi && \
    if [ -s /tmp/genesis.ssz ]; then \
        cp /tmp/genesis.ssz /network-configs/genesis.ssz; \
    fi && \
    if [ -s /tmp/spec.yaml ]; then \
        cp /tmp/spec.yaml /network-configs/spec.yaml; \
    fi && \
    echo "0" > /network-configs/deploy_block.txt && \
    echo "0" > /network-configs/deposit_contract_block.txt && \
    echo "[]" > /network-configs/boot_enr.yaml && \
    rm -f /tmp/chain-spec.yaml /tmp/jwt.hex /tmp/genesis.ssz /tmp/spec.yaml

# Set working directory
WORKDIR /data

# Use our entrypoint script
ENTRYPOINT ["/usr/local/bin/beacon-entrypoint.sh"]
EOF

log "  Building snapshot-beacon:$TAG..."
docker build -t "snapshot-beacon:$TAG" "$BEACON_BUILD_DIR"

if docker images -q "snapshot-beacon:$TAG" &> /dev/null; then
    log "  Beacon image built successfully"
    docker tag "snapshot-beacon:$TAG" "snapshot-beacon:latest"
else
    log "ERROR: Failed to build Beacon image"
    exit 1
fi

# ============================================================================
# Build Lighthouse Validator Image
# ============================================================================

log "Building Lighthouse validator image..."

VALIDATOR_BUILD_DIR="$OUTPUT_DIR/images/validator"

# Copy datadir tarball
cp "$OUTPUT_DIR/datadirs/lighthouse_validator.tar" "$VALIDATOR_BUILD_DIR/"

# Copy chain-spec if available
if [ -f "$OUTPUT_DIR/artifacts/chain-spec.yaml" ]; then
    cp "$OUTPUT_DIR/artifacts/chain-spec.yaml" "$VALIDATOR_BUILD_DIR/"
else
    touch "$VALIDATOR_BUILD_DIR/chain-spec.yaml"
fi

# Copy spec.yaml for Teku
if [ -f "$BEACON_BUILD_DIR/spec.yaml" ]; then
    cp "$BEACON_BUILD_DIR/spec.yaml" "$VALIDATOR_BUILD_DIR/"
else
    echo "PRESET_BASE: 'minimal'" > "$VALIDATOR_BUILD_DIR/spec.yaml"
fi

# Create validator entrypoint script with startup gating
cat > "$VALIDATOR_BUILD_DIR/validator-entrypoint.sh" << 'VALIDATOR_ENTRYPOINT_EOF'
#!/bin/bash
set -e

echo "Validator entrypoint: Waiting for beacon API..."

# Wait for beacon API to be available (only check needed)
MAX_WAIT=60
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    if curl -sf http://beacon:4000/eth/v1/node/health > /dev/null 2>&1; then
        echo "  ✓ Beacon API is responding"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "  ERROR: Beacon API did not become available within $MAX_WAIT seconds"
    exit 1
fi

# Start immediately - beacon needs the validator to produce blocks before it can "sync"
echo "Starting Teku validator client..."

exec teku validator-client \
    --data-path=/data/teku-vc \
    --network=/network-configs/spec.yaml \
    --beacon-node-api-endpoint=http://beacon:4000 \
    --validator-keys=/validator-keys/teku-keys:/validator-keys/teku-secrets \
    --validators-proposer-default-fee-recipient=0x0000000000000000000000000000000000000000 \
    --validators-graffiti="snapshot-validator" \
    --logging=INFO
VALIDATOR_ENTRYPOINT_EOF

chmod +x "$VALIDATOR_BUILD_DIR/validator-entrypoint.sh"

# Create Dockerfile with entrypoint
cat > "$VALIDATOR_BUILD_DIR/Dockerfile" << 'EOF'
FROM consensys/teku:26.2.0

USER root

# Install curl and jq for startup gating
RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*

# Copy validator datadir
COPY lighthouse_validator.tar /tmp/lighthouse_validator.tar

# Copy chain-spec and Teku spec.yaml
COPY chain-spec.yaml /tmp/chain-spec.yaml
COPY spec.yaml /tmp/spec.yaml

# Copy validator entrypoint script
COPY validator-entrypoint.sh /usr/local/bin/validator-entrypoint.sh
RUN chmod +x /usr/local/bin/validator-entrypoint.sh

# Extract datadir and keep validator-keys structure intact
RUN mkdir -p /validator-keys && \
    cd / && \
    tar -xzf /tmp/lighthouse_validator.tar && \
    cp -r validator-data/validator-keys/* /validator-keys/ && \
    rm -rf validator-data && \
    rm /tmp/lighthouse_validator.tar

# Debug: List what was actually extracted
RUN ls -la /validator-keys/ || echo "validator-keys directory not found"

# Verify Teku keys and secrets directories have content
RUN test -d /validator-keys/teku-keys || echo "WARNING: teku-keys directory not found" && \
    test -d /validator-keys/teku-secrets || echo "WARNING: teku-secrets directory not found"

# Create testnet directory with config files
RUN mkdir -p /network-configs && \
    if [ -s /tmp/chain-spec.yaml ]; then \
        cp /tmp/chain-spec.yaml /network-configs/config.yaml; \
    fi && \
    if [ -s /tmp/spec.yaml ]; then \
        cp /tmp/spec.yaml /network-configs/spec.yaml; \
    fi && \
    echo "0" > /network-configs/deploy_block.txt && \
    echo "0" > /network-configs/deposit_contract_block.txt && \
    echo "[]" > /network-configs/boot_enr.yaml && \
    rm -f /tmp/chain-spec.yaml /tmp/spec.yaml

# Set permissions
RUN chmod -R 755 /validator-keys

# Use entrypoint script instead of direct command
ENTRYPOINT ["/usr/local/bin/validator-entrypoint.sh"]
EOF

log "  Building snapshot-validator:$TAG..."
docker build -t "snapshot-validator:$TAG" "$VALIDATOR_BUILD_DIR"

if docker images -q "snapshot-validator:$TAG" &> /dev/null; then
    log "  Validator image built successfully"
    docker tag "snapshot-validator:$TAG" "snapshot-validator:latest"
else
    log "ERROR: Failed to build Validator image"
    exit 1
fi

# ============================================================================
# Save image information
# ============================================================================

log "Saving image metadata..."

cat > "$OUTPUT_DIR/images/IMAGE_INFO.json" << EOF
{
  "tag": "$TAG",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "images": {
    "geth": {
      "name": "snapshot-geth:$TAG",
      "base_image": "$GETH_IMAGE",
      "size": "$(docker images --format "{{.Size}}" snapshot-geth:"$TAG")"
    },
    "beacon": {
      "name": "snapshot-beacon:$TAG",
      "base_image": "$BEACON_IMAGE",
      "size": "$(docker images --format "{{.Size}}" snapshot-beacon:"$TAG")"
    },
    "validator": {
      "name": "snapshot-validator:$TAG",
      "base_image": "$VALIDATOR_IMAGE",
      "size": "$(docker images --format "{{.Size}}" snapshot-validator:"$TAG")"
    }
  }
}
EOF

log "Image metadata saved: $OUTPUT_DIR/images/IMAGE_INFO.json"

# ============================================================================
# Summary
# ============================================================================

log "Docker images built successfully!"
log ""
log "Images created:"
log "  snapshot-geth:$TAG ($(docker images --format "{{.Size}}" snapshot-geth:"$TAG"))"
log "  snapshot-beacon:$TAG ($(docker images --format "{{.Size}}" snapshot-beacon:"$TAG"))"
log "  snapshot-validator:$TAG ($(docker images --format "{{.Size}}" snapshot-validator:"$TAG"))"
log ""
log "To verify images:"
log "  docker images | grep snapshot-"

# Write tag file for compose generation
echo "$TAG" > "$OUTPUT_DIR/images/.tag"

exit 0
