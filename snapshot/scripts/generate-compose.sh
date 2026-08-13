#!/usr/bin/env bash
#
# Docker Compose Generator Script
# Generates docker-compose.yml for snapshot reproduction
#
# Usage: generate-compose.sh [--flavor default|anvil-aggkit] <DISCOVERY_JSON> <OUTPUT_DIR>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Host-port numbering lives in exactly one place.
# shellcheck disable=SC1090,SC1091 # SCRIPT_DIR is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "$SCRIPT_DIR/lib/ports.sh"

FLAVOR="default"
while [ $# -gt 0 ]; do
    case "$1" in
        --flavor)
            FLAVOR="${2:-}"
            shift 2
            ;;
        -*)
            # Do not let an unknown option fall through to `break` and get
            # consumed as a positional -- that silently ran the default flavor.
            echo "ERROR: unknown option: $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# An unrecognised flavor must fail rather than silently select the default
# (geth/lighthouse) code path against an anvil enclave's discovery.
case "$FLAVOR" in
    default | anvil-aggkit) ;;
    *)
        echo "ERROR: unknown flavor: '$FLAVOR' (expected 'default' or 'anvil-aggkit')" >&2
        exit 1
        ;;
esac

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 [--flavor default|anvil-aggkit] <DISCOVERY_JSON> <OUTPUT_DIR>" >&2
    exit 1
fi

DISCOVERY_JSON="$1"
OUTPUT_DIR="$2"

# Check dependencies
# shellcheck disable=SC2043
for cmd in jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: Required command '$cmd' not found" >&2
        exit 1
    fi
done

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting Docker Compose generation"

# Read container info from discovery JSON
if [ ! -f "$DISCOVERY_JSON" ]; then
    log "ERROR: Discovery file not found: $DISCOVERY_JSON"
    exit 1
fi

ENCLAVE_NAME=$(jq -r '.enclave_name' "$DISCOVERY_JSON")

# ============================================================================
# Flavor: anvil-aggkit
#
# Emits a compose file that needs NOTHING else on disk: every service runs a
# derived image with its state/config baked in (see build-images.sh), so there
# are no bind mounts and no volumes. Compose service names are the kurtosis
# service names, which is what makes the captured configs (haproxy backends,
# agglayer full-node-rpcs, aggkit L1/L2 URLs, the aggkit-proxy BridgeURLs map)
# resolve without a single rewrite.
#
# Host ports all come from snapshot/scripts/lib/ports.sh and are individually
# env-overridable; the only one dev-ui CI actually uses is haproxy's
# ${DEVNET_PROXY_PORT:-8555}.
#
# The default flavor continues below this block, untouched.
# ============================================================================

if [ "$FLAVOR" = "anvil-aggkit" ]; then
    STATE_METADATA="$OUTPUT_DIR/state/state-metadata.json"
    IMAGE_INFO="$OUTPUT_DIR/images/IMAGE_INFO.json"
    for f in "$STATE_METADATA" "$IMAGE_INFO"; do
        if [ ! -f "$f" ]; then
            log "ERROR: required input not found: $f"
            exit 1
        fi
    done

    IMAGE_TAG=$(jq -r '.tag' "$IMAGE_INFO")
    IMAGE_PREFIX=$(jq -r '.image_prefix' "$IMAGE_INFO")
    COMPOSE_FILE="$OUTPUT_DIR/docker-compose.yml"
    MOUNTS_COMPOSE_FILE="$OUTPUT_DIR/docker-compose.mounts.yml"

    # Image references are env-overridable too, so the very same compose file
    # works against locally built images (the default) and against the GHCR
    # copies S11 publishes: SNAPSHOT_IMAGE_PREFIX=ghcr.io/0xpolygon/kurtosis-cdk-snapshot-
    image_ref() {
        # shellcheck disable=SC2016 # literal ${VAR:-default} compose-interpolation syntax, not shell expansion
        printf '${SNAPSHOT_IMAGE_PREFIX:-%s}%s:${SNAPSHOT_IMAGE_TAG:-%s}' \
            "$IMAGE_PREFIX" "$1" "$IMAGE_TAG"
    }

    # base_image_of <compose-service> -- the ORIGINAL upstream image ref this
    # service ran under in the enclave (IMAGE_INFO.json's per-service
    # base_image field, written by build-images.sh's record_image()). This is
    # the mounts variant's default for the override-able services (K5 C53/54)
    # -- never the derived snapshot-<svc> image.
    base_image_of() {
        local ref
        ref=$(jq -r --arg svc "$1" '.images[$svc].base_image // empty' "$IMAGE_INFO")
        if [ -z "$ref" ]; then
            log "ERROR: no base_image recorded for service '$1' in $IMAGE_INFO"
            exit 1
        fi
        printf '%s' "$ref"
    }

    L1_SVC=$(jq -r '.l1_anvil.service_name' "$DISCOVERY_JSON")
    AGGLAYER_SVC=$(jq -r '.agglayer.service_name' "$DISCOVERY_JSON")
    PROXY_SVC=$(jq -r '.aggkit_proxy.service_name' "$DISCOVERY_JSON")
    HAPROXY_SVC=$(jq -r '.haproxy.service_name' "$DISCOVERY_JSON")
    DEVUI_SVC=$(jq -r '.dev_ui.service_name' "$DISCOVERY_JSON")
    PREFIXES=$(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON")

    # jq -c '.cmd' gives a JSON array, which is already valid YAML flow syntax.
    cmd_of() {
        jq -c "$1 | .cmd" "$DISCOVERY_JSON"
    }
    entrypoint_of() {
        jq -c "$1 | .entrypoint" "$DISCOVERY_JSON"
    }

    L1_PORT_EXPR=$(snapshot_fixed_port_expr l1_rpc)

    # The haproxy healthcheck (both compose variants) probes exactly the
    # bridge REST route dev-ui CI actually needs, on the FIRST L2 network --
    # same derivation build-images.sh's baked healthcheck.sh already uses
    # (build-images.sh's `FIRST_L2_NETWORK_ID`), read here from
    # state-metadata.json so the compose-level override and the image-baked
    # script never disagree.
    FIRST_L2_NETWORK_ID=$(jq -r '[.chains[] | select(.role == "l2") | .network_id] | first' "$STATE_METADATA")
    if [ -z "$FIRST_L2_NETWORK_ID" ] || [ "$FIRST_L2_NETWORK_ID" = "null" ]; then
        log "ERROR: could not determine first L2 network_id from $STATE_METADATA"
        exit 1
    fi

    # ========================================================================
    # generate_mounts_compose -- the SECOND compose variant (K5 / C53-C55):
    # docker-compose.mounts.yml. Same topology as docker-compose.yml, but
    # points at the on-disk ./config/<svc>/ tree extract-state.sh already
    # wrote instead of relying on a derived image's baked-in COPY.
    #
    # Two explicit design decisions (K5 asks that these be stated, not left
    # to be inferred from omission):
    #
    #  (i) OVERRIDE-ABLE services (agglayer, aggkit-00X, aggkit-proxy-001)
    #      run the BARE UPSTREAM image recorded in IMAGE_INFO.json's
    #      base_image field ($AGGLAYER_IMAGE / $AGGKIT_IMAGE default),
    #      NOT the derived snapshot-<svc> image with the mount merely
    #      shadowing its bake. Reasoning: "override the image" only means
    #      something honest if the un-overridden default is ALSO the bare
    #      image -- otherwise "override" is just swapping one
    #      already-augmented image for another. This is also exactly the
    #      shape aggkit's own e2e envs already use (op-pp-2chains's
    #      aggkit-001: image aggkit:local, bind-mounted config, NO
    #      healthcheck block -- downstream depends via
    #      condition: service_started). aggkit-00X and aggkit-proxy-001
    #      share ONE env var (AGGKIT_IMAGE): the proxy binary ships in the
    #      same aggkit image, entrypoint overridden (same as
    #      docker-compose.yml).
    #
    #      aggkit's own images ARE distroless (no shell at all -- verified:
    #      `docker run --entrypoint sh <aggkit-image>` fails with "exec: sh:
    #      executable file not found"), so aggkit-00X/aggkit-proxy-001
    #      genuinely cannot carry a compose-level healthcheck without
    #      assuming a consumer's override image bundles one; they get NO
    #      healthcheck here, matching aggkit's own env precedent exactly.
    #      Dependents of aggkit-00X (aggkit-proxy-001, haproxy) use
    #      `condition: service_started` for it, unchanged.
    #
    #      agglayer's bare upstream image is DIFFERENT: it is a slim Debian
    #      base, not distroless (verified: it ships /bin/sh -> dash AND
    #      /bin/bash). K5's original design gave agglayer no healthcheck
    #      either, on the assumption it was as tool-less as aggkit -- that
    #      assumption was wrong, and its absence is the root cause of a
    #      reproducible aggsender deadlock fixed here (K5c): aggkit-00X
    #      starting on bare `condition: service_started` races agglayer's
    #      own async gRPC-listener bind. When agglayer isn't yet accepting
    #      connections, aggsender's `SetClaimSyncerNextRequiredBlock` gRPC
    #      call to agglayer stalls for several seconds waiting for the
    #      connection (its GRPC client's MinConnectTimeout=5s) while, in
    #      parallel and with NO dependency on agglayer at all, the claim
    #      syncer's own local autostart sync races ahead past block 100
    #      purely from local L2 chain state (confirmed empirically:
    #      aggkit-001's own logs show the local claim-sync DB already past
    #      block 100 within ~150ms of container start, well before the
    #      first `SetClaimSyncerNextRequiredBlock` attempt resolves ~3.8s
    #      later). Once the local DB has moved past 0, agglayer settling a
    #      certificate later can never re-arm the "block 0" fallback --
    #      `ClaimSync.SetNextRequiredBlock` rejects the mismatch permanently
    #      and aggsender is stuck at `starting_claim_syncer_stage` forever.
    #      A merely-started agglayer process provides no assurance its gRPC
    #      listener is already bound; the fix has to gate on genuine
    #      TCP-level readiness so aggsender's very first gRPC attempt lands
    #      before the local autostart race gets ahead.
    #
    #      Fix (K5c): agglayer gets an explicit COMPOSE-LEVEL healthcheck
    #      here -- `bash -c 'exec 3<>/dev/tcp/127.0.0.1/<grpc-port>'`, a
    #      genuine TCP-connect probe against its own gRPC port, using only
    #      bash's builtin /dev/tcp (confirmed present in the bare image; no
    #      curl/wget/nc needed, so the override risk is limited to "your
    #      AGGLAYER_IMAGE must carry bash", which is true of every
    #      mainstream base image and is stated explicitly in this file's
    #      header comment below). This is stronger than the trivial
    #      `test -f /proc/1/cmdline` process-exists healthcheck aggkit's own
    #      op-pp-2chains gives its agglayer service (same compose-level
    #      mechanism, but "process exists" passes within milliseconds of
    #      container start -- before the gRPC listener binds -- so it would
    #      not close this race; a real listen-socket probe is required, and
    #      the plan's own candidate (A) explicitly allows a TCP form for
    #      exactly this reason). aggkit-00X and aggkit-proxy-001's
    #      `depends_on: agglayer` both move from `condition: service_started`
    #      to `condition: service_healthy` to actually consume this signal.
    #      This does weaken the AGGLAYER_IMAGE override contract slightly:
    #      an override image with no /bin/bash would sit permanently
    #      unhealthy and block aggkit-00X from ever starting (a fail-closed,
    #      loud failure -- not a silent hang) -- see the file header for the
    #      explicit trade-off statement. AGGKIT_IMAGE is the seam the
    #      acceptance criteria actually exercise and is untouched by this.
    #
    #  (ii) haproxy is NOT override-able (no env var -- it was never in
    #       scope) and keeps the SAME derived snapshot-<haproxy-svc> image,
    #       only bind-mounting haproxy.cfg over its baked copy. Its
    #       healthcheck is therefore unchanged and stays meaningful (bare
    #       haproxy ships neither curl nor wget, hence the derived image's
    #       baked busybox). dev-ui behaves the same way (still profiles:
    #       [devui]) -- its healthcheck uses a plain `wget` already present
    #       in the upstream dev-ui base image, so it carries no busybox
    #       dependency either way.
    #
    #  anvil family (L1 + every L2): UNCHANGED from docker-compose.yml --
    #  fully baked, no mount, no override env var. Swapping the anvil image
    #  would lose the captured chain state (K5 explicit non-goal).
    #
    # apply-digests.sh's post-publish digest pin therefore still applies to
    # this file for the anvil family + haproxy + dev-ui (same
    # ${SNAPSHOT_IMAGE_PREFIX:-...}<svc>:${SNAPSHOT_IMAGE_TAG:-...} pattern
    # as docker-compose.yml) but is a no-op, by design, for agglayer/
    # aggkit-00X/aggkit-proxy-001 (their refs here are bare upstream image
    # strings, e.g. ghcr.io/agglayer/aggkit:0.11.0-rc5 -- already a complete,
    # non-derived reference this repo never republishes, so there is no
    # digest of OUR OWN for apply-digests.sh to pin over it).
    # ========================================================================
    generate_mounts_compose() {
        log "Generating anvil-aggkit mounts-variant compose file: $MOUNTS_COMPOSE_FILE"

        local AGGLAYER_BASE_IMAGE AGGKIT_BASE_IMAGE prefix svc this_base

        AGGLAYER_BASE_IMAGE=$(base_image_of "$AGGLAYER_SVC")
        AGGKIT_BASE_IMAGE=$(base_image_of "$PROXY_SVC")
        for prefix in $PREFIXES; do
            svc=$(jq -r --arg p "$prefix" '.l2_chains[$p].aggkit.service_name' "$DISCOVERY_JSON")
            this_base=$(base_image_of "$svc")
            if [ "$this_base" != "$AGGKIT_BASE_IMAGE" ]; then
                log "ERROR: aggkit base image mismatch: $svc=$this_base vs $PROXY_SVC=$AGGKIT_BASE_IMAGE"
                log "       AGGKIT_IMAGE needs one shared default across every aggkit-role service"
                exit 1
            fi
        done

        cat > "$MOUNTS_COMPOSE_FILE" << EOF
# Self-contained devnet snapshot -- flavor: anvil-aggkit, MOUNTS variant
#
# Enclave:   $ENCLAVE_NAME
# Image tag: $IMAGE_TAG
#
# Same topology as docker-compose.yml, but agglayer / aggkit-00X /
# aggkit-proxy-001 run their BARE upstream image and bind-mount
# ./config/<svc>/ (read-only) instead of a derived image's baked-in config;
# haproxy and dev-ui keep their derived image (for baked healthcheck
# tooling) and bind-mount just their own config file. The anvil family is
# unchanged -- baked state only, never bind-mounted.
#
# Image overrides (the whole point of this file): point these at your own
# build to run it against the captured devnet state.
#   AGGLAYER_IMAGE=<your agglayer image>   (default: $AGGLAYER_BASE_IMAGE)
#   AGGKIT_IMAGE=<your aggkit image>       (default: $AGGKIT_BASE_IMAGE)
# aggkit-00X and aggkit-proxy-001 share AGGKIT_IMAGE (the proxy binary ships
# in the same image, entrypoint overridden -- same as docker-compose.yml).
# The anvil family is NOT override-able: swapping it loses the baked state.
#
# K5c: $AGGLAYER_SVC carries a compose-level healthcheck (a bash /dev/tcp
# TCP-connect probe against its own gRPC port -- no curl/wget/nc needed,
# only /bin/bash) so aggkit-00X/aggkit-proxy-001 can gate on
# \`condition: service_healthy\` instead of \`service_started\`; without this,
# aggkit-00X's aggsender races agglayer's own async gRPC-listener bind
# against its own local claim-syncer autostart and permanently deadlocks at
# \`starting_claim_syncer_stage\` (see the comment above generate_mounts_compose
# for the full mechanism). Trade-off: AGGLAYER_IMAGE, unlike AGGKIT_IMAGE, is
# no longer override-able with an arbitrary bash-less image -- an override
# with no /bin/bash sits permanently unhealthy and aggkit-00X never starts (a
# loud, fail-closed error, not a silent hang). aggkit-00X/aggkit-proxy-001
# still carry NO healthcheck of their own (their images are genuinely
# distroless -- no shell at all), matching aggkit's own e2e-env precedent
# for those two services exactly.
#
# apply-digests.sh's post-publish digest pin applies to the anvil family,
# haproxy and dev-ui here (same tag-based ref as docker-compose.yml); it is
# a deliberate no-op for agglayer/aggkit-00X/aggkit-proxy-001, whose refs
# above are already-complete upstream image strings this repo never
# republishes under its own digest.

services:
  $L1_SVC:
    image: $(image_ref "$L1_SVC")
    hostname: $L1_SVC
    ports:
      - "$L1_PORT_EXPR:8545"   # L1 JSON-RPC (debug)
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/bin/sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 40
      start_period: 5s
EOF

        local L2_ANVIL_DEPENDS_M="" PORT_EXPR CHAIN_ID
        for prefix in $PREFIXES; do
            svc=$(jq -r --arg p "$prefix" '.l2_chains[$p].anvil.service_name' "$DISCOVERY_JSON")
            PORT_EXPR=$(snapshot_l2_port_expr "$prefix" http)
            CHAIN_ID=$(jq -r --arg p "$prefix" '.l2_chains[$p].anvil.chain_id' "$DISCOVERY_JSON")
            L2_ANVIL_DEPENDS_M="$L2_ANVIL_DEPENDS_M
      $svc:
        condition: service_healthy"

            cat >> "$MOUNTS_COMPOSE_FILE" << EOF

  $svc:
    image: $(image_ref "$svc")
    hostname: $svc
    ports:
      - "$PORT_EXPR:8545"   # L2 chain $CHAIN_ID JSON-RPC (debug)
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/bin/sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 40
      start_period: 5s
EOF
        done

        cat >> "$MOUNTS_COMPOSE_FILE" << EOF

  $AGGLAYER_SVC:
    image: \${AGGLAYER_IMAGE:-$AGGLAYER_BASE_IMAGE}
    hostname: $AGGLAYER_SVC
    entrypoint: $(entrypoint_of '.agglayer')
    command: $(cmd_of '.agglayer')
    environment:
      - RUST_BACKTRACE=1
    volumes:
      - ./config/$AGGLAYER_SVC/config.toml:/etc/agglayer/config.toml:ro
      - ./config/$AGGLAYER_SVC/aggregator.keystore:/etc/agglayer/aggregator.keystore:ro
    ports:
      - "$(snapshot_fixed_port_expr agglayer_grpc):4443"   # gRPC
      - "$(snapshot_fixed_port_expr agglayer_readrpc):4444"   # read RPC
      - "$(snapshot_fixed_port_expr agglayer_admin):4446"   # admin API
      - "$(snapshot_fixed_port_expr agglayer_metrics):9092"   # prometheus
    depends_on:
      $L1_SVC:
        condition: service_healthy$L2_ANVIL_DEPENDS_M
    restart: unless-stopped
    healthcheck:
      # K5c: genuine TCP-connect probe against agglayer's own gRPC port,
      # using only bash's builtin /dev/tcp (no curl/wget/nc/busybox needed
      # -- confirmed present in the bare upstream image). This is NOT
      # cosmetic: aggkit-00X's aggsender races agglayer's own async
      # gRPC-listener bind against its own local claim-syncer autostart on
      # startup, and a merely-"process started" agglayer loses that race
      # deterministically (see the comment above generate_mounts_compose).
      # A trivial "process exists" check (aggkit's own op-pp-2chains's
      # agglayer healthcheck) passes too early to close this window; the
      # probe below genuinely waits for the listener socket.
      test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/4443"]
      interval: 2s
      timeout: 3s
      retries: 30
      start_period: 10s
EOF

        local AGGKIT_DEPENDS_M="" L2_SVC AGGKIT_SVC
        for prefix in $PREFIXES; do
            L2_SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].anvil.service_name' "$DISCOVERY_JSON")
            AGGKIT_SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].aggkit.service_name' "$DISCOVERY_JSON")
            AGGKIT_DEPENDS_M="$AGGKIT_DEPENDS_M
      $AGGKIT_SVC:
        condition: service_started"

            cat >> "$MOUNTS_COMPOSE_FILE" << EOF

  $AGGKIT_SVC:
    image: \${AGGKIT_IMAGE:-$AGGKIT_BASE_IMAGE}
    hostname: $AGGKIT_SVC
    entrypoint: $(entrypoint_of ".l2_chains[\"$prefix\"].aggkit")
    command: $(cmd_of ".l2_chains[\"$prefix\"].aggkit")
    volumes:
      - ./config/$AGGKIT_SVC:/etc/aggkit:ro
    ports:
      - "$(snapshot_l2_port_expr "$prefix" aggkit_rpc):5576"   # JSON-RPC (debug)
      - "$(snapshot_l2_port_expr "$prefix" aggkit_rest):5577"   # bridge REST API
    depends_on:
      $L1_SVC:
        condition: service_healthy
      $L2_SVC:
        condition: service_healthy
      $AGGLAYER_SVC:
        condition: service_healthy
    restart: unless-stopped
    # aggkit-00X itself carries NO healthcheck -- its image is genuinely
    # distroless (no shell at all: \`docker run --entrypoint sh <image>\`
    # fails with "exec: sh: executable file not found"), matching aggkit's
    # own e2e envs exactly (op-pp-2chains's aggkit-001 has no healthcheck
    # block either). Its OWN depends_on above on $AGGLAYER_SVC is now
    # service_healthy (K5c) -- see the healthcheck comment on $AGGLAYER_SVC.
    # Dependents of aggkit-00X (below) still use condition: service_started.
EOF
        done

        cat >> "$MOUNTS_COMPOSE_FILE" << EOF

  $PROXY_SVC:
    image: \${AGGKIT_IMAGE:-$AGGKIT_BASE_IMAGE}
    hostname: $PROXY_SVC
    entrypoint: $(entrypoint_of '.aggkit_proxy')
    command: $(cmd_of '.aggkit_proxy')
    volumes:
      - ./config/$PROXY_SVC:/etc/aggkit-proxy:ro
    ports:
      - "$(snapshot_fixed_port_expr aggkit_proxy):8080"   # bridge + tracker REST
    depends_on:
      $AGGLAYER_SVC:
        condition: service_healthy$AGGKIT_DEPENDS_M
    restart: unless-stopped
    # aggkit-proxy-001 itself carries NO healthcheck (same distroless image
    # as aggkit-00X). Its depends_on on $AGGLAYER_SVC is service_healthy
    # (K5c); its depends_on on aggkit-00X (\$AGGKIT_DEPENDS_M above) stays
    # service_started, since aggkit-00X has no healthcheck of its own.

  $DEVUI_SVC:
    image: $(image_ref "$DEVUI_SVC")
    hostname: $DEVUI_SVC
    profiles: ["devui"]
    volumes:
      - ./config/$DEVUI_SVC/config.json:/etc/agglayer-dev-ui/config.json:ro
    ports:
      - "$(snapshot_fixed_port_expr dev_ui):80"   # dev-ui (manual use, --profile devui)
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/bin/sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 40
      start_period: 5s

  $HAPROXY_SVC:
    image: $(image_ref "$HAPROXY_SVC")
    hostname: $HAPROXY_SVC
    volumes:
      - ./config/$HAPROXY_SVC/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    ports:
      - "$(snapshot_fixed_port_expr devnet_proxy):80"   # THE dev-ui CI origin
    depends_on:
      $PROXY_SVC:
        condition: service_started
      $L1_SVC:
        condition: service_healthy$L2_ANVIL_DEPENDS_M
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/snapshot/busybox", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:80/aggkitapi/bridge/v1/sync-status?network_id=$FIRST_L2_NETWORK_ID"]
      interval: 3s
      timeout: 10s
      retries: 60
      start_period: 10s

# Bind mounts: agglayer/aggkit-00X/aggkit-proxy-001/haproxy/dev-ui read their
# captured config from ./config/<svc>/ (see extract-state.sh). The anvil
# family has no bind mounts -- state stays baked, never mountable.
EOF

        log "Mounts-variant compose file generated: $MOUNTS_COMPOSE_FILE"
        log "  services: $(grep -cE '^  [a-z0-9-]+:$' "$MOUNTS_COMPOSE_FILE")"
    }

    log "Generating anvil-aggkit compose file: $COMPOSE_FILE"

    cat > "$COMPOSE_FILE" << EOF
# Self-contained devnet snapshot -- flavor: anvil-aggkit
#
# Enclave:   $ENCLAVE_NAME
# Image tag: $IMAGE_TAG
#
# This file is the ENTIRE bundle: every service's state, config and keystores
# are baked into its image, so \`docker compose up -d --wait\` works in an
# otherwise empty directory. There are deliberately no bind mounts and no
# volumes -- restarting from scratch always replays the captured state.
#
# The only endpoint dev-ui CI needs is the haproxy CORS origin on
# \${DEVNET_PROXY_PORT:-$(snapshot_fixed_port devnet_proxy)}, serving /l1rpc, /l2rpc-00X and /aggkitapi.
# Everything else is published for debugging and can be overridden or removed.
#
# Image source override (S11 publishes the same images to GHCR):
#   SNAPSHOT_IMAGE_PREFIX=ghcr.io/0xpolygon/kurtosis-cdk-snapshot-
#   SNAPSHOT_IMAGE_TAG=<published-tag>

services:
  $L1_SVC:
    image: $(image_ref "$L1_SVC")
    hostname: $L1_SVC
    ports:
      - "$L1_PORT_EXPR:8545"   # L1 JSON-RPC (debug)
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/bin/sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 40
      start_period: 5s
EOF

    # ------------------------------------------------------------------
    # L2 anvils
    # ------------------------------------------------------------------
    L2_ANVIL_DEPENDS=""
    for prefix in $PREFIXES; do
        SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].anvil.service_name' "$DISCOVERY_JSON")
        PORT_EXPR=$(snapshot_l2_port_expr "$prefix" http)
        CHAIN_ID=$(jq -r --arg p "$prefix" '.l2_chains[$p].anvil.chain_id' "$DISCOVERY_JSON")
        L2_ANVIL_DEPENDS="$L2_ANVIL_DEPENDS
      $SVC:
        condition: service_healthy"

        cat >> "$COMPOSE_FILE" << EOF

  $SVC:
    image: $(image_ref "$SVC")
    hostname: $SVC
    ports:
      - "$PORT_EXPR:8545"   # L2 chain $CHAIN_ID JSON-RPC (debug)
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/bin/sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 40
      start_period: 5s
EOF
    done

    # ------------------------------------------------------------------
    # agglayer -- needs L1 and every L2 reachable (full-node-rpcs).
    # ------------------------------------------------------------------
    cat >> "$COMPOSE_FILE" << EOF

  $AGGLAYER_SVC:
    image: $(image_ref "$AGGLAYER_SVC")
    hostname: $AGGLAYER_SVC
    entrypoint: $(entrypoint_of '.agglayer')
    command: $(cmd_of '.agglayer')
    environment:
      - RUST_BACKTRACE=1
    ports:
      - "$(snapshot_fixed_port_expr agglayer_grpc):4443"   # gRPC
      - "$(snapshot_fixed_port_expr agglayer_readrpc):4444"   # read RPC
      - "$(snapshot_fixed_port_expr agglayer_admin):4446"   # admin API
      - "$(snapshot_fixed_port_expr agglayer_metrics):9092"   # prometheus
    depends_on:
      $L1_SVC:
        condition: service_healthy$L2_ANVIL_DEPENDS
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/bin/sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 60
      start_period: 10s
EOF

    # ------------------------------------------------------------------
    # aggkit x N -- each process serves both the main aggkit components
    # (aggsender/aggoracle/autoclaim) AND the bridge REST API in one
    # container (--components=...,bridge). There is no separate -bridge
    # sibling service (merged in K1); the healthcheck below proves both the
    # process booted AND the bridge REST API is synced.
    # ------------------------------------------------------------------
    AGGKIT_DEPENDS=""
    for prefix in $PREFIXES; do
        L2_SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].anvil.service_name' "$DISCOVERY_JSON")
        AGGKIT_SVC=$(jq -r --arg p "$prefix" '.l2_chains[$p].aggkit.service_name' "$DISCOVERY_JSON")
        AGGKIT_DEPENDS="$AGGKIT_DEPENDS
      $AGGKIT_SVC:
        condition: service_healthy"

        cat >> "$COMPOSE_FILE" << EOF

  $AGGKIT_SVC:
    image: $(image_ref "$AGGKIT_SVC")
    hostname: $AGGKIT_SVC
    entrypoint: $(entrypoint_of ".l2_chains[\"$prefix\"].aggkit")
    command: $(cmd_of ".l2_chains[\"$prefix\"].aggkit")
    ports:
      - "$(snapshot_l2_port_expr "$prefix" aggkit_rpc):5576"   # JSON-RPC (debug)
      - "$(snapshot_l2_port_expr "$prefix" aggkit_rest):5577"   # bridge REST API
    depends_on:
      $L1_SVC:
        condition: service_healthy
      $L2_SVC:
        condition: service_healthy
      $AGGLAYER_SVC:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/snapshot/busybox", "sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 60
      start_period: 10s
EOF
    done

    # ------------------------------------------------------------------
    # aggkit-proxy (proxy,tracker) -- fronts every chain's bridge REST API.
    # ------------------------------------------------------------------
    cat >> "$COMPOSE_FILE" << EOF

  $PROXY_SVC:
    image: $(image_ref "$PROXY_SVC")
    hostname: $PROXY_SVC
    entrypoint: $(entrypoint_of '.aggkit_proxy')
    command: $(cmd_of '.aggkit_proxy')
    ports:
      - "$(snapshot_fixed_port_expr aggkit_proxy):8080"   # bridge + tracker REST
    depends_on:
      $AGGLAYER_SVC:
        condition: service_healthy$AGGKIT_DEPENDS
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/snapshot/busybox", "sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 60
      start_period: 10s

  $DEVUI_SVC:
    image: $(image_ref "$DEVUI_SVC")
    hostname: $DEVUI_SVC
    # K5 (devui-under-test.md (c)): NOT started by a plain \`docker compose
    # up\` / \`up -d --wait\` -- CI never uses this container (only bare \`/\`
    # through haproxy's default_backend does, and nothing CI-relevant hits
    # bare \`/\`). Bring it up for manual/local debugging with
    # \`docker compose --profile devui up -d\`.
    profiles: ["devui"]
    ports:
      - "$(snapshot_fixed_port_expr dev_ui):80"   # dev-ui (manual use, --profile devui)
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/bin/sh", "/snapshot/healthcheck.sh"]
      interval: 3s
      timeout: 10s
      retries: 40
      start_period: 5s

  $HAPROXY_SVC:
    image: $(image_ref "$HAPROXY_SVC")
    hostname: $HAPROXY_SVC
    ports:
      - "$(snapshot_fixed_port_expr devnet_proxy):80"   # THE dev-ui CI origin
    depends_on:
      $PROXY_SVC:
        condition: service_healthy
      $L1_SVC:
        condition: service_healthy$L2_ANVIL_DEPENDS
    restart: unless-stopped
    # K5: the image's baked /snapshot/healthcheck.sh probes BOTH
    # /aggkitapi/bridge/v1/sync-status AND bare / (routed to $DEVUI_SVC by
    # haproxy.cfg's default_backend). Since $DEVUI_SVC is profile-gated off
    # by default, bare / has no live backend and that baked script would
    # fail forever, hanging \`docker compose up -d --wait\`. This
    # compose-level override fully replaces the image's HEALTHCHECK and
    # probes only the route CI actually needs, reusing the busybox binary
    # already baked into this image.
    healthcheck:
      test: ["CMD", "/snapshot/busybox", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:80/aggkitapi/bridge/v1/sync-status?network_id=$FIRST_L2_NETWORK_ID"]
      interval: 3s
      timeout: 10s
      retries: 60
      start_period: 10s

# No volumes and no bind mounts: all state and config is baked into the images.
EOF

    log "Compose file generated: $COMPOSE_FILE"
    log "  services: $(grep -cE '^  [a-z0-9-]+:$' "$COMPOSE_FILE")"
    log "  bind mounts: $(grep -c 'volumes:' "$COMPOSE_FILE" || true) (must be 0)"

    if grep -q 'volumes:' "$COMPOSE_FILE"; then
        log "ERROR: generated compose file contains volumes/bind mounts"
        exit 1
    fi

    generate_mounts_compose

    exit 0
fi

# Check if agglayer was discovered
AGGLAYER_FOUND=$(jq -r '.agglayer.found' "$DISCOVERY_JSON")
if [ "$AGGLAYER_FOUND" = "true" ]; then
    AGGLAYER_IMAGE=$(jq -r '.agglayer.image' "$DISCOVERY_JSON")
    log "Agglayer found: $AGGLAYER_IMAGE"
fi

# Read image tag
TAG=""
if [ -f "$OUTPUT_DIR/images/.tag" ]; then
    TAG=$(cat "$OUTPUT_DIR/images/.tag")
else
    log "WARNING: Image tag file not found, using 'latest'"
    TAG="latest"
fi

log "Generating compose file for images with tag: $TAG"

# Read checkpoint for genesis hash
GENESIS_HASH="unknown"
if [ -f "$OUTPUT_DIR/metadata/checkpoint.json" ]; then
    GENESIS_HASH=$(jq -r '.l1_state.genesis_hash' "$OUTPUT_DIR/metadata/checkpoint.json" 2>/dev/null || echo "unknown")
fi

# Get snapshot ID from directory name for container naming
SNAPSHOT_ID=$(basename "$OUTPUT_DIR")

log "Using snapshot ID: $SNAPSHOT_ID"

# ============================================================================
# Generate docker-compose.yml
# ============================================================================

log "Creating docker-compose.yml..."

cat > "$OUTPUT_DIR/docker-compose.yml" << EOF
# Ethereum L1 Snapshot Environment
# Enclave: $ENCLAVE_NAME
# Tag: $TAG
# Genesis: $GENESIS_HASH

services:
  geth:
    image: snapshot-geth:$TAG
    container_name: $SNAPSHOT_ID-geth
    hostname: geth
    command:
      - "--http"
      - "--http.addr=0.0.0.0"
      - "--http.port=8545"
      - "--http.vhosts=*"
      - "--http.corsdomain=*"
      - "--http.api=admin,engine,net,eth,web3,debug,txpool"
      - "--ws"
      - "--ws.addr=0.0.0.0"
      - "--ws.port=8546"
      - "--ws.origins=*"
      - "--ws.api=admin,engine,net,eth,web3,debug,txpool"
      - "--authrpc.addr=0.0.0.0"
      - "--authrpc.port=8551"
      - "--authrpc.vhosts=*"
      - "--authrpc.jwtsecret=/jwt/jwtsecret"
      - "--datadir=/data/geth/execution-data"
      - "--port=30303"
      - "--discovery.port=30303"
      - "--syncmode=full"
      - "--gcmode=archive"
      - "--networkid=271828"
      - "--metrics"
      - "--metrics.addr=0.0.0.0"
      - "--metrics.port=9001"
      - "--allow-insecure-unlock"
      - "--nodiscover"
    ports:
      - "8545:8545"    # HTTP RPC
      - "8546:8546"    # WebSocket RPC
      - "8551:8551"    # Engine API
      - "30303:30303"  # P2P TCP
      - "30303:30303/udp"  # P2P UDP
      - "9001:9001"    # Metrics
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:8545"]
      interval: 2s
      timeout: 3s
      retries: 3
      start_period: 10s

  beacon:
    image: snapshot-beacon:$TAG
    container_name: $SNAPSHOT_ID-beacon
    hostname: beacon
    # Note: command is handled by beacon-entrypoint.sh which patches genesis time and starts Teku
    ports:
      - "4000:4000"    # Beacon API
      - "9000:9000"    # P2P TCP
      - "9000:9000/udp"  # P2P UDP
      - "5054:5054"    # Metrics
    depends_on:
      geth:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/eth/v1/node/health"]
      interval: 3s
      timeout: 5s
      retries: 5
      start_period: 30s

  validator:
    image: snapshot-validator:$TAG
    container_name: $SNAPSHOT_ID-validator
    hostname: validator
    # Command is handled by validator-entrypoint.sh which gates startup on beacon sync
    depends_on:
      beacon:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "pgrep", "-f", "validator-client"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 60s
EOF

# Add agglayer service if found
if [ "$AGGLAYER_FOUND" = "true" ]; then
    cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  agglayer:
    image: $AGGLAYER_IMAGE
    container_name: $SNAPSHOT_ID-agglayer
    hostname: agglayer
    entrypoint: ["/usr/local/bin/agglayer"]
    command:
      - "run"
      - "--cfg"
      - "/etc/agglayer/config.toml"
    volumes:
      - ./config/agglayer/config.toml:/etc/agglayer/config.toml:ro
      - ./config/agglayer/aggregator.keystore:/etc/agglayer/aggregator.keystore:ro
    ports:
      - "4443:4443"    # gRPC RPC
      - "4444:4444"    # Read RPC
      - "4446:4446"    # Admin API
      - "9092:9092"    # Prometheus metrics
    depends_on:
      geth:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "sh", "-c", "test -f /proc/1/cmdline"]
      interval: 2s
      timeout: 3s
      retries: 3
      start_period: 10s
    environment:
      - RUST_BACKTRACE=1
EOF
    log "Agglayer service added to docker-compose.yml"
fi

# ============================================================================
# Add L2 services (op-reth + op-node + aggkit) if found
# ============================================================================

L2_CHAINS_COUNT=$(jq -r '.l2_chains | length // 0' "$DISCOVERY_JSON" 2>/dev/null || echo "0")

if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    log "Adding L2 services to docker-compose.yml..."

    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        log "  Adding L2 network: $prefix"

        # Get container info
        OP_RETH_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_reth_sequencer.image" "$DISCOVERY_JSON")
        OP_NODE_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_node_sequencer.image" "$DISCOVERY_JSON")
        AGGKIT_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].aggkit.image // empty" "$DISCOVERY_JSON")

        # Port offsets for this L2 network -- see snapshot/scripts/lib/ports.sh
        # (network 001 -> 11xxx, network 002 -> 12xxx).
        L2_HTTP_PORT=$(snapshot_l2_port "$prefix" http)
        L2_WS_PORT=$(snapshot_l2_port "$prefix" ws)
        L2_ENGINE_PORT=$(snapshot_l2_port "$prefix" engine)
        L2_NODE_RPC_PORT=$(snapshot_l2_port "$prefix" node_rpc)
        L2_NODE_METRICS_PORT=$(snapshot_l2_port "$prefix" node_metrics)
        L2_AGGKIT_RPC_PORT=$(snapshot_l2_port "$prefix" aggkit_rpc)
        L2_AGGKIT_REST_PORT=$(snapshot_l2_port "$prefix" aggkit_rest)

        # ====================================================================
        # op-reth service (with runtime L2 genesis timestamp patching)
        # ====================================================================

        # Copy entrypoint script to config dir for mounting
        cp "$(dirname "$0")/op-reth-entrypoint.sh" "$OUTPUT_DIR/config/$prefix/"

        cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  op-reth-$prefix:
    image: $OP_RETH_IMAGE
    container_name: $SNAPSHOT_ID-op-reth-$prefix
    hostname: op-reth-$prefix
    entrypoint: ["/bin/sh", "/entrypoint/op-reth-entrypoint.sh"]
    volumes:
      - ./config/$prefix/jwt.hex:/jwt/jwtsecret:ro
      - ./config/$prefix/l2-genesis.json:/genesis-ro/l2-genesis.json:ro
      - ./config/$prefix/rollup.json:/rollup-ro/rollup.json:ro
      - ./config/$prefix/op-reth-entrypoint.sh:/entrypoint/op-reth-entrypoint.sh:ro
      - l2-shared-$prefix:/shared
    ports:
      - "$L2_HTTP_PORT:8545"    # HTTP RPC
      - "$L2_WS_PORT:8546"    # WebSocket RPC
      - "$L2_ENGINE_PORT:8551"    # Engine API
    depends_on:
      geth:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:8545"]
      interval: 2s
      timeout: 3s
      retries: 3
      start_period: 180s
EOF

        log "    ✓ op-reth-$prefix service added"

        # ====================================================================
        # op-node service (with runtime rollup.json timestamp patching)
        # ====================================================================

        # Copy entrypoint script to config dir for mounting
        cp "$(dirname "$0")/op-node-entrypoint.sh" "$OUTPUT_DIR/config/$prefix/"

        cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  op-node-$prefix:
    image: $OP_NODE_IMAGE
    container_name: $SNAPSHOT_ID-op-node-$prefix
    hostname: op-node-$prefix
    entrypoint: ["/bin/sh", "/entrypoint/op-node-entrypoint.sh"]
    environment:
      - OP_RETH_HOST=op-reth-$prefix
    volumes:
      - ./config/$prefix/rollup.json:/rollup-ro/rollup.json:ro
      - ./config/$prefix/l1-genesis.json:/network-configs/l1-genesis.json:ro
      - ./config/$prefix/jwt.hex:/jwt/jwtsecret:ro
      - ./config/$prefix/op-node-entrypoint.sh:/entrypoint/op-node-entrypoint.sh:ro
      - l2-shared-$prefix:/shared:ro
    ports:
      - "$L2_NODE_RPC_PORT:8547"    # RPC
      - "$L2_NODE_METRICS_PORT:7300"    # Metrics
    depends_on:
      geth:
        condition: service_healthy
      beacon:
        condition: service_healthy
      op-reth-$prefix:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "--post-data={\"jsonrpc\":\"2.0\",\"method\":\"optimism_syncStatus\",\"params\":[],\"id\":1}", "--header=Content-Type:application/json", "http://localhost:8547"]
      interval: 2s
      timeout: 3s
      retries: 3
      start_period: 240s
EOF

        log "    ✓ op-node-$prefix service added"

        # ====================================================================
        # aggkit service (if present)
        # ====================================================================

        if [ -n "$AGGKIT_IMAGE" ] && [ "$AGGKIT_IMAGE" != "null" ]; then
            # Build depends_on section dynamically
            AGGKIT_DEPENDS="      geth:
        condition: service_healthy
      op-reth-$prefix:
        condition: service_healthy
      op-node-$prefix:
        condition: service_healthy"

            # Add agglayer dependency if present
            if [ "$AGGLAYER_FOUND" = "true" ]; then
                AGGKIT_DEPENDS="$AGGKIT_DEPENDS
      agglayer:
        condition: service_healthy"
            fi

            cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  aggkit-$prefix:
    image: $AGGKIT_IMAGE
    container_name: $SNAPSHOT_ID-aggkit-$prefix
    hostname: aggkit-$prefix
    entrypoint: ["/usr/local/bin/aggkit"]
    command:
      - "run"
      - "--cfg=/etc/aggkit/config.toml"
      - "--components=aggsender,aggoracle,bridge"
    volumes:
      - ./config/$prefix/aggkit-config.toml:/etc/aggkit/config.toml:ro
      - ./config/$prefix/sequencer.keystore:/etc/aggkit/sequencer.keystore:ro
      - ./config/$prefix/aggoracle.keystore:/etc/aggkit/aggoracle.keystore:ro
      - ./config/$prefix/sovereignadmin.keystore:/etc/aggkit/sovereignadmin.keystore:ro
    ports:
      - "$L2_AGGKIT_RPC_PORT:5576"    # RPC
      - "$L2_AGGKIT_REST_PORT:5577"    # REST API
    depends_on:
$AGGKIT_DEPENDS
    restart: unless-stopped
    environment:
      - RUST_BACKTRACE=1
EOF

            log "    ✓ aggkit-$prefix service added"
        fi

        log "  L2 network $prefix services added to docker-compose"
    done

    log "All L2 services added to docker-compose.yml"
else
    log "No L2 networks to add"
fi

# Add shared volumes for L2 genesis info exchange between op-reth and op-node
if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

volumes:
EOF
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF
  l2-shared-$prefix:
EOF
    done
else
    cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

# No volumes - all state is baked into images
EOF
fi

cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF
# L1 state is baked in, L2 starts fresh with config-only mounts
# Agglayer and AggKit use host-mounted config files (read-only)
EOF

log "Docker Compose file generated: $OUTPUT_DIR/docker-compose.yml"

# ============================================================================
# Generate helper scripts
# ============================================================================

log "Creating helper scripts..."

# Start script
cat > "$OUTPUT_DIR/start-snapshot.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

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
echo "  curl -s http://localhost:8545 -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' | jq -r '.result' | xargs printf '%d\n'"
EOF

chmod +x "$OUTPUT_DIR/start-snapshot.sh"

# Stop script
cat > "$OUTPUT_DIR/stop-snapshot.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail

echo "Stopping Ethereum L1 snapshot..."
docker-compose -f docker-compose.yml down

echo "Snapshot stopped."
EOF

chmod +x "$OUTPUT_DIR/stop-snapshot.sh"

# Query script
cat > "$OUTPUT_DIR/query-state.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Querying L1 state..."
echo ""

# Block number
BLOCK_HEX=$(curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')
BLOCK_DEC=$((16#${BLOCK_HEX#0x}))

echo "Current block number: $BLOCK_DEC (hex: $BLOCK_HEX)"

# Beacon head
BEACON_HEAD=$(curl -s http://localhost:4000/eth/v1/beacon/headers/head | jq -r '.data.header.message.slot' 2>/dev/null || echo "unknown")
echo "Beacon head slot: $BEACON_HEAD"

# Syncing status
SYNCING=$(curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq -r '.result')

if [ "$SYNCING" = "false" ]; then
    echo "Sync status: Synchronized"
else
    echo "Sync status: Syncing - $SYNCING"
fi

echo ""
echo "For continuous monitoring:"
echo "  watch -n 2 ./query-state.sh"
EOF

chmod +x "$OUTPUT_DIR/query-state.sh"

log "Helper scripts created (will be cleaned up after snapshot finalization):"
log "  start-snapshot.sh - Temporary helper for testing"
log "  stop-snapshot.sh - Temporary helper for testing"
log "  query-state.sh - Temporary helper for testing"

# ============================================================================
# Create usage guide
# ============================================================================

cat > "$OUTPUT_DIR/USAGE.md" << EOF
# Snapshot Usage Guide

## Quick Start

1. **Start the snapshot:**
   \`\`\`bash
   ./start-snapshot.sh
   \`\`\`

2. **Query state:**
   \`\`\`bash
   ./query-state.sh
   \`\`\`

3. **Stop the snapshot:**
   \`\`\`bash
   ./stop-snapshot.sh
   \`\`\`

## Network Summary

This snapshot includes a \`summary.json\` file with comprehensive information about all networks, services, and accounts:

- **Contract Addresses**: All deployed smart contracts for L1, Agglayer, and each L2 network
- **Service URLs**: Both internal (Docker) and external (localhost) URLs for all services
- **Accounts**: All relevant accounts including:
  - Pre-funded genesis accounts
  - Validator accounts
  - Sequencer, AggOracle, and other operational accounts
  - Account roles and descriptions

View the summary:
\`\`\`bash
cat summary.json | jq
\`\`\`

## Manual Operations

### Start services
\`\`\`bash
docker-compose -f docker-compose.yml up -d
\`\`\`

### View logs
\`\`\`bash
docker-compose -f docker-compose.yml logs -f
\`\`\`

### Check service status
\`\`\`bash
docker-compose -f docker-compose.yml ps
\`\`\`

### Query block number
\`\`\`bash
curl -s http://localhost:8545 \\
  -X POST \\
  -H "Content-Type: application/json" \\
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \\
  | jq -r '.result' | xargs printf '%d\\n'
\`\`\`

### Query beacon chain
\`\`\`bash
curl -s http://localhost:4000/eth/v1/beacon/headers/head | jq
\`\`\`

### Stop services
\`\`\`bash
docker-compose -f docker-compose.yml down
\`\`\`

## Endpoints

- **Geth HTTP RPC:** http://localhost:8545
- **Geth WebSocket:** ws://localhost:8546
- **Geth Engine API:** http://localhost:8551
- **Beacon API:** http://localhost:4000
- **Geth Metrics:** http://localhost:9001/debug/metrics/prometheus
- **Beacon Metrics:** http://localhost:5054/metrics
- **Validator Metrics:** http://localhost:5064/metrics
EOF

if [ "$AGGLAYER_FOUND" = "true" ]; then
    cat >> "$OUTPUT_DIR/USAGE.md" << EOF
- **Agglayer gRPC:** http://localhost:4443
- **Agglayer Read RPC:** http://localhost:4444
- **Agglayer Admin API:** http://localhost:4446
- **Agglayer Metrics:** http://localhost:9092/metrics
EOF
fi

# Add L2 endpoints if present
if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    cat >> "$OUTPUT_DIR/USAGE.md" << EOF

### L2 Network Endpoints

EOF

    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        # Ports for documentation -- see snapshot/scripts/lib/ports.sh
        L2_HTTP_PORT=$(snapshot_l2_port "$prefix" http)
        L2_WS_PORT=$(snapshot_l2_port "$prefix" ws)
        L2_ENGINE_PORT=$(snapshot_l2_port "$prefix" engine)
        L2_NODE_RPC_PORT=$(snapshot_l2_port "$prefix" node_rpc)
        L2_NODE_METRICS_PORT=$(snapshot_l2_port "$prefix" node_metrics)
        L2_AGGKIT_RPC_PORT=$(snapshot_l2_port "$prefix" aggkit_rpc)
        L2_AGGKIT_REST_PORT=$(snapshot_l2_port "$prefix" aggkit_rest)

        cat >> "$OUTPUT_DIR/USAGE.md" << EOF

**L2 Network $prefix:**
- **op-reth HTTP RPC:** http://localhost:$L2_HTTP_PORT
- **op-reth WebSocket:** ws://localhost:$L2_WS_PORT
- **op-reth Engine API:** http://localhost:$L2_ENGINE_PORT
- **op-node RPC:** http://localhost:$L2_NODE_RPC_PORT
- **op-node Metrics:** http://localhost:$L2_NODE_METRICS_PORT
EOF

        # Add aggkit endpoints if present for this network
        AGGKIT_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].aggkit.image // empty" "$DISCOVERY_JSON")
        if [ -n "$AGGKIT_IMAGE" ] && [ "$AGGKIT_IMAGE" != "null" ]; then
            cat >> "$OUTPUT_DIR/USAGE.md" << EOF
- **aggkit-$prefix RPC:** http://localhost:$L2_AGGKIT_RPC_PORT
- **aggkit-$prefix REST API:** http://localhost:$L2_AGGKIT_REST_PORT
EOF
        fi
    done
fi

cat >> "$OUTPUT_DIR/USAGE.md" << EOF

## Network Details

- **Network:** Using Docker's default bridge network
- **Container Communication:** Services communicate using container hostnames
EOF

# Build service and container names lists
SERVICES_LIST="geth, beacon, validator"
CONTAINER_NAMES_LIST="$SNAPSHOT_ID-geth, $SNAPSHOT_ID-beacon, $SNAPSHOT_ID-validator"

if [ "$AGGLAYER_FOUND" = "true" ]; then
    SERVICES_LIST="$SERVICES_LIST, agglayer"
    CONTAINER_NAMES_LIST="$CONTAINER_NAMES_LIST, $SNAPSHOT_ID-agglayer"
fi

if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        SERVICES_LIST="$SERVICES_LIST, op-reth-$prefix, op-node-$prefix"
        CONTAINER_NAMES_LIST="$CONTAINER_NAMES_LIST, $SNAPSHOT_ID-op-reth-$prefix, $SNAPSHOT_ID-op-node-$prefix"

        AGGKIT_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].aggkit.image // empty" "$DISCOVERY_JSON")
        if [ -n "$AGGKIT_IMAGE" ] && [ "$AGGKIT_IMAGE" != "null" ]; then
            SERVICES_LIST="$SERVICES_LIST, aggkit-$prefix"
            CONTAINER_NAMES_LIST="$CONTAINER_NAMES_LIST, $SNAPSHOT_ID-aggkit-$prefix"
        fi
    done
fi

cat >> "$OUTPUT_DIR/USAGE.md" << EOF
- **Services:** $SERVICES_LIST
- **Container Names:** $CONTAINER_NAMES_LIST
EOF

cat >> "$OUTPUT_DIR/USAGE.md" << EOF

Each snapshot uses unique container names based on its snapshot ID.
Services run on Docker's default bridge network and communicate using container hostnames.

**Note:** If running multiple snapshots, you'll need to modify port mappings in the
docker-compose.yml file to avoid port conflicts, or remove port mappings and access
services via container names.
EOF

if [ "$AGGLAYER_FOUND" = "true" ]; then
    cat >> "$OUTPUT_DIR/USAGE.md" << EOF

### Agglayer Notes

The agglayer service is included in this snapshot with adapted configuration:
- L1 connectivity is configured to use the snapshot's geth service
- L2 RPC endpoints are commented out in the config (L2 stack not included)
- Configuration files are mounted from \`./config/agglayer/\` directory
- No state is persisted (agglayer starts fresh each time)

**To use agglayer with L2:**
1. Deploy your L2 services (e.g., cdk-erigon-rpc)
2. Edit \`config/agglayer/config.toml\` to uncomment and update L2 RPC endpoints
3. Restart the agglayer service

**Agglayer Configuration:**
- Config: \`./config/agglayer/config.toml\`
- Keystore: \`./config/agglayer/aggregator.keystore\`
- Original backup: \`./config/agglayer/config.toml.bak\`
EOF
fi

# Add L2 notes if present
if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    cat >> "$OUTPUT_DIR/USAGE.md" << EOF

### L2 Networks Notes

This snapshot includes $L2_CHAINS_COUNT L2 network(s) with adapted configuration:

**Architecture:**
- L2 services start with fresh state (no baked-in data)
- Configuration files are mounted from \`./config/<network-prefix>/\` directories
- Each L2 network has isolated config and services
- L1 connectivity is configured to use the snapshot's geth and beacon services

**L2 Components per network:**
- **op-reth**: Execution layer (Optimism Reth fork)
- **op-node**: Consensus/rollup layer
- **aggkit**: AggSender and AggOracle for Agglayer integration (if present)

**Configuration Files:**
EOF

    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        cat >> "$OUTPUT_DIR/USAGE.md" << EOF
- Network $prefix: \`./config/$prefix/\`
  - \`rollup.json\` - Rollup configuration
  - \`l1-genesis.json\` - L1 genesis for op-node
  - \`l2-genesis.json\` - L2 genesis (optional)
  - \`jwt.hex\` - JWT secret for op-reth <-> op-node auth
EOF

        AGGKIT_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].aggkit.image // empty" "$DISCOVERY_JSON")
        if [ -n "$AGGKIT_IMAGE" ] && [ "$AGGKIT_IMAGE" != "null" ]; then
            cat >> "$OUTPUT_DIR/USAGE.md" << EOF
  - \`aggkit-config.toml\` - AggKit configuration
  - \`*.keystore\` - Private keys for AggKit components
EOF
        fi
    done

    cat >> "$OUTPUT_DIR/USAGE.md" << EOF

**Important:**
- L2 services start with empty state - they will sync from L1 on first run
- Port mappings use network prefix (e.g., network 001 uses ports 8540X)
- All configurations have been adapted for docker-compose hostnames
- Original configs are backed up with \`.bak\` extension

**Query L2 Block Number:**
\`\`\`bash
# For network 001 (port 10545)
curl -s http://localhost:10545 -X POST -H "Content-Type: application/json" \\
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \\
  | jq -r '.result' | xargs printf '%d\\n'

# For network 002 (port 11545)
curl -s http://localhost:11545 -X POST -H "Content-Type: application/json" \\
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \\
  | jq -r '.result' | xargs printf '%d\\n'
\`\`\`

**Port Mapping Scheme:**
- Network 001: Base port 10000 (10545 for HTTP RPC, 10546 for WS, etc.)
- Network 002: Base port 11000 (11545 for HTTP RPC, 11546 for WS, etc.)
- Network N: Base port (10000 + N*1000) + service offset

EOF
fi

cat >> "$OUTPUT_DIR/USAGE.md" << EOF

## Troubleshooting

### Services not starting
Check logs:
\`\`\`bash
docker-compose -f docker-compose.yml logs
\`\`\`

### Port conflicts
Ensure ports 8545, 8546, 4000, 9000, 30303 are not in use:
\`\`\`bash
netstat -tuln | grep -E '8545|8546|4000|9000|30303'
\`\`\`

### Data issues
Verify images exist:
\`\`\`bash
docker images | grep snapshot-
\`\`\`

## Verification

Run the verification script:
\`\`\`bash
cd /home/aigent/kurtosis-cdk
./snapshot/verify.sh $OUTPUT_DIR
\`\`\`

This will:
1. Start the snapshot
2. Verify initial block number matches checkpoint
3. Wait and verify blocks continue progressing
4. Report verification results
EOF

log "Docker Compose generation complete!"
log "Note: Temporary helper files will be removed after snapshot verification"

exit 0
