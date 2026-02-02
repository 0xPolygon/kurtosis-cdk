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

# Read checkpoint for network configuration
GENESIS_HASH="unknown"
if [ -f "$OUTPUT_DIR/metadata/checkpoint.json" ]; then
    GENESIS_HASH=$(jq -r '.l1_state.genesis_hash' "$OUTPUT_DIR/metadata/checkpoint.json" 2>/dev/null || echo "unknown")
fi

# Generate unique network name based on snapshot directory
SNAPSHOT_ID=$(basename "$OUTPUT_DIR")
NETWORK_NAME="snapshot-${SNAPSHOT_ID}-l1"

log "Using network name: $NETWORK_NAME"

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
    container_name: ${SNAPSHOT_ID}-geth
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
    networks:
      - l1-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:8545"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s

  beacon:
    image: snapshot-beacon:$TAG
    container_name: ${SNAPSHOT_ID}-beacon
    hostname: beacon
    command:
      - "lighthouse"
      - "beacon_node"
      - "--testnet-dir=/network-configs"
      - "--datadir=/data/lighthouse/beacon-data"
      - "--http"
      - "--http-address=0.0.0.0"
      - "--http-port=4000"
      - "--execution-endpoint=http://geth:8551"
      - "--execution-jwt=/jwt/jwtsecret"
      - "--port=9000"
      - "--discovery-port=9000"
      - "--target-peers=0"
      - "--disable-peer-scoring"
      - "--disable-backfill-rate-limiting"
      - "--enr-address=127.0.0.1"
      - "--enr-udp-port=9000"
      - "--enr-tcp-port=9000"
      - "--metrics"
      - "--metrics-address=0.0.0.0"
      - "--metrics-port=5054"
    ports:
      - "4000:4000"    # Beacon API
      - "9000:9000"    # P2P TCP
      - "9000:9000/udp"  # P2P UDP
      - "5054:5054"    # Metrics
    networks:
      - l1-network
    depends_on:
      geth:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "sh", "-c", "curl -f -s http://localhost:4000/eth/v1/node/health || curl -s -o /dev/null -w '%{http_code}' http://localhost:4000/eth/v1/node/health | grep -q '206'"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 60s

  validator:
    image: snapshot-validator:$TAG
    container_name: ${SNAPSHOT_ID}-validator
    hostname: validator
    command:
      - "lighthouse"
      - "validator_client"
      - "--testnet-dir=/network-configs"
      - "--validators-dir=/validator-keys/keys"
      - "--secrets-dir=/validator-keys/secrets"
      - "--beacon-nodes=http://beacon:4000"
      - "--beacon-nodes-sync-tolerances=1000,100,200"
      - "--suggested-fee-recipient=0x0000000000000000000000000000000000000000"
      - "--metrics"
      - "--metrics-address=0.0.0.0"
      - "--metrics-port=5064"
      - "--init-slashing-protection"
    networks:
      - l1-network
    depends_on:
      beacon:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:5064/metrics"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 60s
EOF

# Add agglayer service if found
if [ "$AGGLAYER_FOUND" = "true" ]; then
    cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

  agglayer:
    image: $AGGLAYER_IMAGE
    container_name: ${SNAPSHOT_ID}-agglayer
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
    networks:
      - l1-network
    depends_on:
      geth:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:9092/metrics"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 30s
    environment:
      - RUST_BACKTRACE=1
EOF
    log "Agglayer service added to docker-compose.yml"
fi

cat >> "$OUTPUT_DIR/docker-compose.yml" << EOF

networks:
  l1-network:
    name: $NETWORK_NAME
    driver: bridge

# No volumes - all state is baked into images
# Agglayer uses host-mounted config files (read-only)
EOF

log "Docker Compose file generated: $OUTPUT_DIR/docker-compose.yml"

# ============================================================================
# Generate helper scripts
# ============================================================================

log "Creating helper scripts..."

# Start script
cat > "$OUTPUT_DIR/start-snapshot.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Starting Ethereum L1 snapshot..."
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
cat > "$OUTPUT_DIR/stop-snapshot.sh" << 'EOF'
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

log "Helper scripts created:"
log "  start-snapshot.sh - Start the snapshot"
log "  stop-snapshot.sh - Stop the snapshot"
log "  query-state.sh - Query L1 state"

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

cat >> "$OUTPUT_DIR/USAGE.md" << EOF

## Network Details

- **Network Name:** snapshot-${SNAPSHOT_ID}-l1 (unique per snapshot)
- **Network Type:** Bridge
EOF

if [ "$AGGLAYER_FOUND" = "true" ]; then
    cat >> "$OUTPUT_DIR/USAGE.md" << EOF
- **Services:** geth, beacon, validator, agglayer
- **Container Names:** ${SNAPSHOT_ID}-geth, ${SNAPSHOT_ID}-beacon, ${SNAPSHOT_ID}-validator, ${SNAPSHOT_ID}-agglayer
EOF
else
    cat >> "$OUTPUT_DIR/USAGE.md" << EOF
- **Services:** geth, beacon, validator
- **Container Names:** ${SNAPSHOT_ID}-geth, ${SNAPSHOT_ID}-beacon, ${SNAPSHOT_ID}-validator
EOF
fi

cat >> "$OUTPUT_DIR/USAGE.md" << EOF

Each snapshot uses a unique network and container names based on its snapshot ID,
allowing multiple snapshots to run simultaneously without network conflicts.

**Note:** If running multiple snapshots, you'll need to modify port mappings in the
docker-compose.yml file to avoid port conflicts, or remove port mappings and access
services via container names from within the Docker network.
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

log "Usage guide created: $OUTPUT_DIR/USAGE.md"

log "Docker Compose generation complete!"

exit 0
