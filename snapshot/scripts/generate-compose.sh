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
    command:
      - "teku"
      - "validator-client"
      - "--data-path=/data/teku-vc"
      - "--network=/network-configs/spec.yaml"
      - "--beacon-node-api-endpoint=http://beacon:4000"
      - "--validator-keys=/validator-keys/keys:/validator-keys/secrets"
      - "--validators-proposer-default-fee-recipient=0x0000000000000000000000000000000000000000"
      - "--logging=INFO"
    depends_on:
      beacon:
        condition: service_healthy
    restart: unless-stopped
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
# Add L2 services (op-geth + op-node + aggkit) if found
# ============================================================================

L2_CHAINS_COUNT=$(jq -r '.l2_chains | length // 0' "$DISCOVERY_JSON" 2>/dev/null || echo "0")

if [ "$L2_CHAINS_COUNT" != "null" ] && [ "$L2_CHAINS_COUNT" -gt 0 ]; then
    log "Adding L2 services to docker-compose.yml..."

    for prefix in $(jq -r '.l2_chains | keys[]' "$DISCOVERY_JSON" 2>/dev/null); do
        log "  Adding L2 network: $prefix"

        # Get container info
        OP_GETH_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_geth_sequencer.image" "$DISCOVERY_JSON")
        OP_NODE_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].op_node_sequencer.image" "$DISCOVERY_JSON")
        AGGKIT_IMAGE=$(jq -r ".l2_chains[\"$prefix\"].aggkit.image // empty" "$DISCOVERY_JSON")

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

        # ====================================================================
        # op-geth service
        # ====================================================================

        cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  op-geth-$prefix:
    image: $OP_GETH_IMAGE
    container_name: $SNAPSHOT_ID-op-geth-$prefix
    hostname: op-geth-$prefix
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        if [ ! -d "/data/geth" ]; then
          echo "Initializing op-geth with genesis..."
          geth init --datadir=/data /genesis.json
        fi
        exec geth \
          --http \
          --http.addr=0.0.0.0 \
          --http.port=8545 \
          --http.vhosts='*' \
          --http.corsdomain='*' \
          --http.api=admin,engine,net,eth,web3,debug,txpool \
          --ws \
          --ws.addr=0.0.0.0 \
          --ws.port=8546 \
          --ws.origins='*' \
          --ws.api=admin,engine,net,eth,web3,debug,txpool \
          --authrpc.addr=0.0.0.0 \
          --authrpc.port=8551 \
          --authrpc.vhosts='*' \
          --authrpc.jwtsecret=/jwt/jwtsecret \
          --datadir=/data \
          --port=30303 \
          --discovery.port=30303 \
          --syncmode=full \
          --gcmode=archive \
          --metrics \
          --metrics.addr=0.0.0.0 \
          --metrics.port=9001 \
          --rollup.disabletxpoolgossip \
          --nodiscover
    volumes:
      - ./config/$prefix/jwt.hex:/jwt/jwtsecret:ro
      - ./config/$prefix/l2-genesis.json:/genesis.json:ro
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
      start_period: 10s
EOF

        log "    ✓ op-geth-$prefix service added"

        # ====================================================================
        # op-node service
        # ====================================================================

        cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  op-node-$prefix:
    image: $OP_NODE_IMAGE
    container_name: $SNAPSHOT_ID-op-node-$prefix
    hostname: op-node-$prefix
    command:
      - "op-node"
      - "--rollup.config=/network-configs/rollup.json"
      - "--l1=http://geth:8545"
      - "--l1.beacon=http://beacon:4000"
      - "--l2=http://op-geth-$prefix:8551"
      - "--l2.jwt-secret=/jwt/jwtsecret"
      - "--rpc.addr=0.0.0.0"
      - "--rpc.port=8547"
      - "--rpc.enable-admin"
      - "--p2p.disable"
      - "--sequencer.enabled"
      - "--sequencer.l1-confs=0"
      - "--rollup.l1-chain-config=/network-configs/l1-genesis.json"
      - "--metrics.enabled"
      - "--metrics.addr=0.0.0.0"
      - "--metrics.port=7300"
    volumes:
      - ./config/$prefix/rollup.json:/network-configs/rollup.json:ro
      - ./config/$prefix/l1-genesis.json:/network-configs/l1-genesis.json:ro
      - ./config/$prefix/jwt.hex:/jwt/jwtsecret:ro
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
      start_period: 20s
EOF

        log "    ✓ op-node-$prefix service added"

        # ====================================================================
        # aggkit service (if present)
        # ====================================================================

        if [ -n "$AGGKIT_IMAGE" ] && [ "$AGGKIT_IMAGE" != "null" ]; then
            # Build depends_on section dynamically
            AGGKIT_DEPENDS="      geth:
        condition: service_healthy
      op-geth-$prefix:
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

cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

# No volumes - all state is baked into images
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
- **op-geth**: Execution layer (Optimism Geth fork)
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
