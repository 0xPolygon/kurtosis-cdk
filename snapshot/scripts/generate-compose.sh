#!/usr/bin/env bash
#
# Docker Compose Generator Script
# Generates docker-compose.yml for snapshot reproduction
#
# Usage: generate-compose.sh <DISCOVERY_JSON> <OUTPUT_DIR>
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
    # Alias the restored L1 EL under its original kurtosis service name so
    # components that hardcode the kurtosis L1 RPC hostname keep resolving it.
    # cdk-erigon's captured config.yaml references zkevm.l1-rpc-url as
    # http://el-1-geth-lighthouse:8545; op-stack instead has its L1 hostnames
    # rewritten to "geth" during adaptation. The alias is harmless for op-stack.
    networks:
      default:
        aliases:
          - el-1-geth-lighthouse
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

        # Chain type drives which EL/CL services we emit (op-stack vs cdk-erigon)
        CHAIN_TYPE=$(jq -r ".l2_chains[\"$prefix\"].chain_type // \"op-stack\"" "$DISCOVERY_JSON")
        log "    Chain type: $CHAIN_TYPE"

        # Get container info
        OP_RETH_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_reth_sequencer.image // empty" "$DISCOVERY_JSON")
        OP_NODE_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_node_sequencer.image // empty" "$DISCOVERY_JSON")
        AGGKIT_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].aggkit.image // empty" "$DISCOVERY_JSON")
        CDK_ERIGON_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].cdk_erigon_sequencer.image // empty" "$DISCOVERY_JSON")
        OP_SUCCINCT_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_succinct_proposer.image // empty" "$DISCOVERY_JSON")
        DAC_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].cdk_data_availability.image // empty" "$DISCOVERY_JSON")

        # Calculate port offsets for this L2 network (prefix as number, e.g., 001 -> 1)
        # Network 001: ports 10545, 10546, 10547, ...
        # Network 002: ports 11545, 11546, 11547, ...
        PREFIX_NUM=$((10#$prefix))
        L2_HTTP_PORT=$((10000 + PREFIX_NUM * 1000 + 545))
        L2_WS_PORT=$((10000 + PREFIX_NUM * 1000 + 546))
        L2_ENGINE_PORT=$((10000 + PREFIX_NUM * 1000 + 551))
        L2_NODE_RPC_PORT=$((10000 + PREFIX_NUM * 1000 + 547))
        L2_NODE_METRICS_PORT=$((10000 + PREFIX_NUM * 1000 + 300))
        L2_AGGKIT_RPC_PORT=$((10000 + PREFIX_NUM * 1000 + 576))
        L2_AGGKIT_REST_PORT=$((10000 + PREFIX_NUM * 1000 + 577))
        L2_DAC_PORT=$((10000 + PREFIX_NUM * 1000 + 484))
        L2_SUCCINCT_METRICS_PORT=$((10000 + PREFIX_NUM * 1000 + 80))

      if [ "$CHAIN_TYPE" = "op-stack" ]; then
        # ====================================================================
        # L2 execution-layer service (with runtime L2 genesis timestamp patching)
        #
        # NOTE: The restored EL service is ALWAYS emitted under the loader-facing
        # service key "op-geth-<prefix>" because the consumed summary schema
        # (aggkit loader.go / op-pp) expects the logical key "op-geth". The
        # ACTUAL client binary, however, depends on the discovered image:
        #   - op-pp / classic op-stack: the discovered image is genuinely
        #     op-geth, so we run op-geth-entrypoint.sh (apk add jq; geth init;
        #     exec geth ...).
        #   - FEP / op-succinct: the discovered EL image is op-reth, on which
        #     `apk`/`geth` do not exist (it would exit 127). We must instead run
        #     op-reth-entrypoint.sh (apt install jq/wget; op-reth init; exec
        #     op-reth node ...).
        # The selection is conditional on the actual image so op-pp stays
        # byte-identical while op-reth-backed FEP envs boot correctly. The
        # summary.json logical key stays "op-geth" in BOTH cases.
        # ====================================================================

        # Detect the real EL client from the discovered image string.
        EL_ENTRYPOINT_SCRIPT="op-geth-entrypoint.sh"
        # Healthcheck differs by client: op-geth answers a bare HTTP GET on the
        # RPC port (200), but op-reth (like most JSON-RPC servers) rejects GET
        # with 405, so the op-geth `wget GET` probe would never pass and op-node
        # (gated on EL service_healthy) would never start. Use a JSON-RPC POST
        # for op-reth so the healthcheck reflects real EL readiness.
        EL_HEALTHCHECK_TEST='["CMD", "wget", "-q", "-O", "-", "http://localhost:8545"]'
        case "$OP_RETH_IMAGE" in
            *op-reth*|*/reth:*|*reth:*)
                EL_ENTRYPOINT_SCRIPT="op-reth-entrypoint.sh"
                EL_HEALTHCHECK_TEST='["CMD", "wget", "-q", "-O", "-", "--post-data={\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}", "--header=Content-Type:application/json", "http://localhost:8545"]'
                ;;
        esac
        log "    EL image $OP_RETH_IMAGE -> entrypoint $EL_ENTRYPOINT_SCRIPT"

        # Copy entrypoint script to config dir for mounting
        cp "$(dirname "$0")/$EL_ENTRYPOINT_SCRIPT" "$OUTPUT_DIR/config/$prefix/"

        cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  op-geth-$prefix:
    image: $OP_RETH_IMAGE
    container_name: $SNAPSHOT_ID-op-geth-$prefix
    hostname: op-geth-$prefix
    entrypoint: ["/bin/sh", "/entrypoint/$EL_ENTRYPOINT_SCRIPT"]
    volumes:
      - ./config/$prefix/jwt.hex:/jwt/jwtsecret:ro
      - ./config/$prefix/l2-genesis.json:/genesis-ro/l2-genesis.json:ro
      - ./config/$prefix/rollup.json:/rollup-ro/rollup.json:ro
      - ./config/$prefix/$EL_ENTRYPOINT_SCRIPT:/entrypoint/$EL_ENTRYPOINT_SCRIPT:ro
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
      test: $EL_HEALTHCHECK_TEST
      interval: 2s
      timeout: 3s
      retries: 3
      start_period: 180s
EOF

        log "    ✓ op-geth-$prefix service added"

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
      - OP_GETH_HOST=op-geth-$prefix
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
      op-geth-$prefix:
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
        # op-batcher service (op-stack only)
        #
        # The batcher posts the sequencer's L2 batches to the L1 batch-inbox;
        # this is what advances the L2 safe/finalized heads. Without it the
        # restored L2 sequences unsafe blocks forever but never finalizes (and,
        # in FEP mode, the ZKP has no L1 batch data to prove against).
        #
        # The batcher is stateless: its full launch CMD (incl. the funded
        # --private-key, DA type, poll/safety params, and the L1/L2/rollup RPC
        # endpoints) was captured verbatim by discover-containers.sh. We rewrite
        # ONLY the kurtosis enclave service hostnames to the restored compose
        # hostnames (geth / op-geth-<prefix> / op-node-<prefix>) and replay the
        # entrypoint + cmd unchanged, so the restored batcher signs L1 txs from
        # the same funded batcher account.
        # ====================================================================
        OP_BATCHER_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_batcher.image // empty" "$DISCOVERY_JSON")
        if [ -n "$OP_BATCHER_IMAGE" ] && [ "$OP_BATCHER_IMAGE" != "null" ]; then
            log "    Adding op-batcher-$prefix service..."

            # Build the rewritten entrypoint+cmd YAML lists. Each captured token
            # has its enclave hostnames swapped for restored-compose hostnames.
            OP_BATCHER_ARGS_YAML=$(jq -r \
                --arg prefix "$prefix" '
                ((.l2_chains[$prefix].op_batcher.entrypoint // [])
                 + (.l2_chains[$prefix].op_batcher.cmd // []))[]
                | gsub("el-1-geth-lighthouse:8545"; "geth:8545")
                | gsub("op-el-1-op-reth-op-node-" + $prefix + ":8545"; "op-geth-" + $prefix + ":8545")
                | gsub("op-el-2-op-reth-op-node-" + $prefix + ":8545"; "op-geth-" + $prefix + ":8545")
                | gsub("op-cl-1-op-node-op-reth-" + $prefix + ":8547"; "op-node-" + $prefix + ":8547")
                | gsub("op-cl-2-op-node-op-reth-" + $prefix + ":8547"; "op-node-" + $prefix + ":8547")
                | "      - \"" + (gsub("\""; "\\\"")) + "\""
                ' "$DISCOVERY_JSON")

            # Batcher RPC admin port (per-prefix host mapping, mirrors other
            # services: 10000 + prefix*1000 + 548).
            L2_BATCHER_RPC_PORT=$((10000 + PREFIX_NUM * 1000 + 548))

            {
                echo ""
                echo "  op-batcher-$prefix:"
                echo "    image: $OP_BATCHER_IMAGE"
                echo "    container_name: $SNAPSHOT_ID-op-batcher-$prefix"
                echo "    hostname: op-batcher-$prefix"
                echo "    command:"
                echo "$OP_BATCHER_ARGS_YAML"
                echo "    ports:"
                echo "      - \"$L2_BATCHER_RPC_PORT:8548\"    # batcher RPC/admin"
                echo "    depends_on:"
                echo "      geth:"
                echo "        condition: service_healthy"
                echo "      op-geth-$prefix:"
                echo "        condition: service_healthy"
                echo "      op-node-$prefix:"
                echo "        condition: service_healthy"
                echo "    restart: unless-stopped"
            } >> "$OUTPUT_DIR/docker-compose.yml"

            log "    ✓ op-batcher-$prefix service added"
        fi
      fi  # end op-stack EL/CL emission

        # ====================================================================
        # cdk-erigon service (multi-chain, incl. custom-gas chains)
        #
        # Distinct datadir layout from op-geth: the erigon chain DB tar
        # (cdk-erigon-<prefix>.tar) is mounted into /home/erigon/data and the
        # /etc/cdk-erigon config (carrying the custom gas-token chain config)
        # is bind-mounted. Emitted as service "cdk-erigon-<prefix>" so it is
        # distinguishable from op-geth in the restored compose.
        # ====================================================================
        if [ "$CHAIN_TYPE" = "cdk-erigon" ] && [ -n "$CDK_ERIGON_IMAGE" ] && [ "$CDK_ERIGON_IMAGE" != "null" ]; then
            cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  cdk-erigon-$prefix:
    image: $CDK_ERIGON_IMAGE
    container_name: $SNAPSHOT_ID-cdk-erigon-$prefix
    hostname: cdk-erigon-$prefix
    # Alias the restored EL under the kurtosis RPC service name as well, since
    # the captured aggkit config dials the L2 over http://cdk-erigon-rpc-<prefix>:8545.
    # In the snapshot the single restored erigon node serves both roles.
    networks:
      default:
        aliases:
          - cdk-erigon-rpc-$prefix
    # Run as root (uid/gid 0), matching how kurtosis launches cdk-erigon
    # (user=User(uid=0, gid=0)). The image's default user is "erigon", which
    # cannot create its datadir under the root-owned named volume, so without
    # this the node panics with "mkdir /home/erigon/data/...: permission denied".
    user: "0:0"
    environment:
      - CDK_ERIGON_SEQUENCER=1
    # The image ENTRYPOINT is already ["cdk-erigon"]; pass only the flags so we
    # don't turn "cdk-erigon" into an (invalid) subcommand. Set entrypoint
    # explicitly for clarity/robustness across image variants.
    entrypoint: ["cdk-erigon"]
    command: ["--config", "/etc/cdk-erigon/config.yaml"]
    volumes:
      - ./config/$prefix/cdk-erigon/etc:/etc/cdk-erigon:ro
      - cdk-erigon-data-$prefix:/home/erigon/data
    ports:
      - "$L2_HTTP_PORT:8545"    # HTTP RPC
      - "$L2_WS_PORT:8546"    # WebSocket RPC
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
            log "    ✓ cdk-erigon-$prefix service added"
        fi

        # ====================================================================
        # op-succinct proposer (FEP prover/proposer)
        #
        # Wired but NOT settled: the proposer is restored with its captured env
        # so it can resume proving after restore, but no settlement is forced
        # at snapshot time (consistent with snapshot.sh STEP-3 L1-stop-before-
        # extract). The prover DB (postgres) starts fresh unless a dump exists.
        # ====================================================================
        if [ -n "$OP_SUCCINCT_IMAGE" ] && [ "$OP_SUCCINCT_IMAGE" != "null" ]; then
            cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  postgres-$prefix:
    image: postgres:16-alpine
    container_name: $SNAPSHOT_ID-postgres-$prefix
    hostname: postgres-$prefix
    environment:
      - POSTGRES_USER=op_succinct_user
      - POSTGRES_PASSWORD=op_succinct_password
      - POSTGRES_DB=op_succinct_db
    volumes:
      - op-succinct-pg-$prefix:/var/lib/postgresql/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U op_succinct_user -d op_succinct_db"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s

  op-succinct-proposer-$prefix:
    image: $OP_SUCCINCT_IMAGE
    container_name: $SNAPSHOT_ID-op-succinct-proposer-$prefix
    hostname: op-succinct-proposer-$prefix
    # env_file restores the captured proposer wiring (L2OO addr, prover mode,
    # agglayer gateway). Generated from proposer-env.json during restore.
    env_file:
      - ./config/$prefix/op-succinct/proposer.env
    volumes:
      # Writable: the validity-proposer writes derived config/workspace files
      # under /app/configs at startup; a read-only mount makes it fail with
      # "Read-only file system (os error 30)" before it can run.
      - ./config/$prefix/op-succinct/configs:/app/configs:rw
    ports:
      - "$L2_SUCCINCT_METRICS_PORT:8080"    # Prometheus metrics
    depends_on:
      geth:
        condition: service_healthy
      postgres-$prefix:
        condition: service_healthy
    restart: unless-stopped
EOF
            # Materialize the env_file + a fresh-DB seed from the captured state.
            if [ -f "$OUTPUT_DIR/config/$prefix/op-succinct/proposer-env.json" ]; then
                PROPOSER_ENV="$OUTPUT_DIR/config/$prefix/op-succinct/proposer.env"
                jq -r '.[]' "$OUTPUT_DIR/config/$prefix/op-succinct/proposer-env.json" \
                    > "$PROPOSER_ENV" 2>/dev/null || true
                # Rewrite the captured kurtosis service hostnames to the restored
                # docker-compose service names, exactly as adapt-l2-config.sh does
                # for the aggkit/agglayer configs. Without this the proposer's
                # L2_RPC / L2_NODE_RPC / L1 endpoints point at the original
                # enclave DNS names (op-el-1-op-reth-op-node-<prefix>,
                # op-cl-1-op-node-op-reth-<prefix>, el-1-geth-lighthouse,
                # cl-1-lighthouse-geth) which do not exist in the compose network,
                # so the proposer restart-loops on "Temporary failure in name
                # resolution".
                sed -i "s|op-el-1-op-reth-op-node-$prefix:8545|op-geth-$prefix:8545|g" "$PROPOSER_ENV"
                sed -i "s|op-cl-1-op-node-op-reth-$prefix:8547|op-node-$prefix:8547|g" "$PROPOSER_ENV"
                sed -i "s|el-1-geth-lighthouse:8545|geth:8545|g" "$PROPOSER_ENV"
                sed -i "s|cl-1-lighthouse-geth:4000|beacon:4000|g" "$PROPOSER_ENV"
            else
                : > "$OUTPUT_DIR/config/$prefix/op-succinct/proposer.env" 2>/dev/null || true
            fi
            log "    ✓ op-succinct-proposer-$prefix (FEP, wired/not-settled) + postgres-$prefix added"
        fi

        # ====================================================================
        # cdk-data-availability (committee / DAC member)
        # Restored with its config + dac.keystore so the committee signs again.
        # ====================================================================
        if [ -n "$DAC_IMAGE" ] && [ "$DAC_IMAGE" != "null" ]; then
            DAC_DEPENDS="      geth:
        condition: service_healthy"
            if [ "$CHAIN_TYPE" = "cdk-erigon" ]; then
                DAC_DEPENDS="$DAC_DEPENDS
      cdk-erigon-$prefix:
        condition: service_healthy"
            fi
            cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  cdk-data-availability-$prefix:
    image: $DAC_IMAGE
    container_name: $SNAPSHOT_ID-cdk-data-availability-$prefix
    hostname: cdk-data-availability-$prefix
    entrypoint: ["/app/cdk-data-availability"]
    command: ["run", "--cfg", "/etc/cdk-data-availability/config.toml"]
    volumes:
      - ./config/$prefix/dac/etc:/etc/cdk-data-availability:ro
    ports:
      - "$L2_DAC_PORT:8484"    # DAC RPC
    depends_on:
$DAC_DEPENDS
    restart: unless-stopped
EOF
            log "    ✓ cdk-data-availability-$prefix (committee/DAC) service added"
        fi

        # ====================================================================
        # aggkit service (if present) — attaches to op-stack OR cdk-erigon
        # ====================================================================

        if [ -n "$AGGKIT_IMAGE" ] && [ "$AGGKIT_IMAGE" != "null" ]; then
            # Build depends_on section dynamically based on chain type
            AGGKIT_DEPENDS="      geth:
        condition: service_healthy"
            if [ "$CHAIN_TYPE" = "op-stack" ]; then
                AGGKIT_DEPENDS="$AGGKIT_DEPENDS
      op-geth-$prefix:
        condition: service_healthy
      op-node-$prefix:
        condition: service_healthy"
            elif [ "$CHAIN_TYPE" = "cdk-erigon" ]; then
                AGGKIT_DEPENDS="$AGGKIT_DEPENDS
      cdk-erigon-$prefix:
        condition: service_healthy"
            fi

            # Add agglayer dependency if present
            if [ "$AGGLAYER_FOUND" = "true" ]; then
                AGGKIT_DEPENDS="$AGGKIT_DEPENDS
      agglayer:
        condition: service_healthy"
            fi

            # aggkit components per sequencer type. op-stack chains restore their
            # full state (incl. the initialized L2 GER manager) so the aggoracle
            # component runs. cdk-erigon chains in a snapshot-clean capture boot
            # their EL from a fresh datadir and re-derive blocks as a sequencer,
            # which does NOT replay the post-genesis L2 GER-manager initialization
            # (globalExitRootUpdater() reverts), so the aggoracle component would
            # crash-loop on startup. The aggsender + bridge components do not need
            # it; we run those so the bridge REST service (the loader's readiness
            # dependency) and aggsender come up. This keeps the restored env
            # bootable and loadable without changing op-stack behavior.
            AGGKIT_COMPONENTS="aggsender,aggoracle,bridge"
            if [ "$CHAIN_TYPE" = "cdk-erigon" ]; then
                AGGKIT_COMPONENTS="aggsender,bridge"
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
      - "--components=$AGGKIT_COMPONENTS"
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

        # ====================================================================
        # AggOracle committee member services (extra aggkit aggoracle signers)
        # Each restored with its own config + aggoracle.keystore so the on-chain
        # AggOracleCommittee keeps its full M-of-N signer set after restore.
        # ====================================================================
        COMMITTEE_COUNT=$(jq -r ".l2_chains[\"$prefix\"].aggoracle_committee_members | length // 0" "$DISCOVERY_JSON" 2>/dev/null || echo 0)
        if [ "$COMMITTEE_COUNT" != "0" ] && [ "$COMMITTEE_COUNT" != "null" ] && [ -n "$COMMITTEE_COUNT" ]; then
            cm_idx=0
            while [ "$cm_idx" -lt "$COMMITTEE_COUNT" ]; do
                CM_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].aggoracle_committee_members[$cm_idx].image // empty" "$DISCOVERY_JSON")
                CM_PAD=$(printf '%03d' "$cm_idx")
                CM_RPC_PORT=$((10000 + PREFIX_NUM * 1000 + 600 + cm_idx))
                if [ -n "$CM_IMAGE" ] && [ "$CM_IMAGE" != "null" ]; then
                    CM_DEPENDS="      geth:
        condition: service_healthy"
                    if [ "$CHAIN_TYPE" = "op-stack" ]; then
                        CM_DEPENDS="$CM_DEPENDS
      op-geth-$prefix:
        condition: service_healthy
      op-node-$prefix:
        condition: service_healthy"
                    fi
                    if [ "$AGGLAYER_FOUND" = "true" ]; then
                        CM_DEPENDS="$CM_DEPENDS
      agglayer:
        condition: service_healthy"
                    fi
                    cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  aggkit-$prefix-aggoracle-committee-$CM_PAD:
    image: $CM_IMAGE
    container_name: $SNAPSHOT_ID-aggkit-$prefix-aggoracle-committee-$CM_PAD
    hostname: aggkit-$prefix-aggoracle-committee-$CM_PAD
    entrypoint: ["/usr/local/bin/aggkit"]
    command:
      - "run"
      - "--cfg=/etc/aggkit/config.toml"
      - "--components=aggoracle"
    volumes:
      - ./config/$prefix/committee/$CM_PAD/etc:/etc/aggkit:ro
    ports:
      - "$CM_RPC_PORT:5576"    # committee member RPC
    depends_on:
$CM_DEPENDS
    restart: unless-stopped
    environment:
      - RUST_BACKTRACE=1
EOF
                    log "    ✓ aggkit-$prefix-aggoracle-committee-$CM_PAD service added"
                fi
                cm_idx=$((cm_idx + 1))
            done
        fi

        log "  L2 network $prefix services added to docker-compose"
    done

    log "All L2 services added to docker-compose.yml"
else
    log "No L2 networks to add"
fi

# Add named volumes:
#  - l2-shared-<prefix>: op-reth <-> op-node genesis handshake (op-stack)
#  - cdk-erigon-data-<prefix>: cdk-erigon chain DB (cdk-erigon)
#  - op-succinct-pg-<prefix>: FEP prover postgres DB (op-succinct)
if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

volumes:
EOF
    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        CHAIN_TYPE=$(jq -r ".l2_chains[\"$prefix\"].chain_type // \"op-stack\"" "$DISCOVERY_JSON")
        OP_SUCCINCT_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_succinct_proposer.image // empty" "$DISCOVERY_JSON")

        if [ "$CHAIN_TYPE" = "op-stack" ]; then
            cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF
  l2-shared-$prefix:
EOF
        elif [ "$CHAIN_TYPE" = "cdk-erigon" ]; then
            cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF
  cdk-erigon-data-$prefix:
EOF
        fi

        if [ -n "$OP_SUCCINCT_IMAGE" ] && [ "$OP_SUCCINCT_IMAGE" != "null" ]; then
            cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF
  op-succinct-pg-$prefix:
EOF
        fi
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
        # Calculate ports for documentation
        PREFIX_NUM=$((10#$prefix))
        L2_HTTP_PORT=$((10000 + PREFIX_NUM * 1000 + 545))
        L2_WS_PORT=$((10000 + PREFIX_NUM * 1000 + 546))
        L2_ENGINE_PORT=$((10000 + PREFIX_NUM * 1000 + 551))
        L2_NODE_RPC_PORT=$((10000 + PREFIX_NUM * 1000 + 547))
        L2_NODE_METRICS_PORT=$((10000 + PREFIX_NUM * 1000 + 300))
        L2_AGGKIT_RPC_PORT=$((10000 + PREFIX_NUM * 1000 + 576))
        L2_AGGKIT_REST_PORT=$((10000 + PREFIX_NUM * 1000 + 577))

        cat >> "$OUTPUT_DIR/USAGE.md" << EOF

**L2 Network $prefix:**
- **op-geth HTTP RPC:** http://localhost:$L2_HTTP_PORT
- **op-geth WebSocket:** ws://localhost:$L2_WS_PORT
- **op-geth Engine API:** http://localhost:$L2_ENGINE_PORT
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
        SERVICES_LIST="$SERVICES_LIST, op-geth-$prefix, op-node-$prefix"
        CONTAINER_NAMES_LIST="$CONTAINER_NAMES_LIST, $SNAPSHOT_ID-op-geth-$prefix, $SNAPSHOT_ID-op-node-$prefix"

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
- **op-geth**: Execution layer (op-stack EL; Kurtosis sequencer-type label is "op-reth")
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
  - \`jwt.hex\` - JWT secret for op-geth <-> op-node auth
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
