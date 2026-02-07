#!/usr/bin/env bash
#
# Ethereum L1 Snapshot Tool
# Main orchestrator for creating deterministic, repeatable L1 snapshots
#
# Usage: snapshot.sh <ENCLAVE_NAME> [--out <DIR>] [--tag <TAG>]
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
OUTPUT_BASE_DIR="snapshots"
TAG_SUFFIX=""
ENCLAVE_NAME=""
SKIP_VERIFY=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "\n${GREEN}========================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${GREEN}$*${NC}" | tee -a "$LOG_FILE"
    echo -e "${GREEN}========================================${NC}\n" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
Ethereum L1 Snapshot Tool

Usage:
  $0 <ENCLAVE_NAME> [OPTIONS]

Arguments:
  ENCLAVE_NAME        Name of the Kurtosis enclave to snapshot

Options:
  --out <DIR>         Output directory (default: snapshots)
  --tag <TAG>         Custom tag suffix for images
  --skip-verify       Skip automated verification step
  -h, --help          Show this help message

Examples:
  # Basic snapshot
  $0 snapshot-test

  # Custom output directory
  $0 snapshot-test --out ./my-snapshots

  # With custom tag
  $0 snapshot-test --tag v1.0.0

  # Skip verification (faster)
  $0 snapshot-test --skip-verify

Description:
  Creates a complete, deterministic snapshot of an Ethereum L1 devnet:
  - Discovers and stops all L1 containers (geth, beacon, validator)
  - Extracts all datadirs and configuration files
  - Restarts the original enclave to resume block production
  - Builds Docker images with state baked in
  - Generates Docker Compose for reproduction
  - Automatically verifies the snapshot works correctly

Output Structure:
  <OUTPUT_DIR>/<ENCLAVE>-<TIMESTAMP>/
    ├── datadirs/                      # State tarballs
    ├── artifacts/                     # Configuration files
    ├── metadata/                      # Checkpoint and checksums
    ├── images/                        # Dockerfiles
    ├── docker-compose.snapshot.yml    # Compose file
    ├── summary.json                   # Network summary (contracts, URLs, accounts)
    ├── start-snapshot.sh              # Helper scripts
    ├── stop-snapshot.sh
    ├── query-state.sh
    ├── USAGE.md
    └── snapshot.log

Requirements:
  - Docker
  - Kurtosis CLI
  - jq, curl, tar
  - Running Kurtosis enclave with L1 services

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        --out)
            OUTPUT_BASE_DIR="$2"
            shift 2
            ;;
        --tag)
            TAG_SUFFIX="$2"
            shift 2
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$ENCLAVE_NAME" ]; then
                ENCLAVE_NAME="$1"
            else
                log_error "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

# Validate enclave name provided
if [ -z "$ENCLAVE_NAME" ]; then
    log_error "Enclave name is required"
    usage
fi

# ============================================================================
# Setup
# ============================================================================

# Create timestamped output directory
TIMESTAMP=$(date -u +'%Y%m%d-%H%M%S')
SNAPSHOT_NAME="${ENCLAVE_NAME}-${TIMESTAMP}"
OUTPUT_DIR="${OUTPUT_BASE_DIR}/${SNAPSHOT_NAME}"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Convert to absolute path (required for Docker volume mounts)
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

# Initialize log file
LOG_FILE="$OUTPUT_DIR/snapshot.log"
touch "$LOG_FILE"

log_step "Ethereum L1 Snapshot Tool"
log "Snapshot name: $SNAPSHOT_NAME"
log "Enclave: $ENCLAVE_NAME"
log "Output directory: $OUTPUT_DIR"
log "Timestamp: $TIMESTAMP"

if [ -n "$TAG_SUFFIX" ]; then
    log "Custom tag: $TAG_SUFFIX"
fi

# ============================================================================
# Preflight Checks
# ============================================================================

log_step "STEP 0: Preflight Checks"

# Check required commands
log "Checking required commands..."
MISSING_CMDS=()

for cmd in docker kurtosis jq curl tar sha256sum; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_CMDS+=("$cmd")
    else
        log "  ✓ $cmd"
    fi
done

if [ ${#MISSING_CMDS[@]} -gt 0 ]; then
    log_error "Missing required commands: ${MISSING_CMDS[*]}"
    exit 1
fi

# Check Docker is running
if ! docker info &> /dev/null; then
    log_error "Docker is not running or not accessible"
    exit 1
fi
log "  ✓ Docker is running"

# Check scripts exist
log "Checking snapshot scripts..."
SCRIPTS=(
    "$SCRIPT_DIR/scripts/discover-containers.sh"
    "$SCRIPT_DIR/scripts/extract-state.sh"
    "$SCRIPT_DIR/scripts/adapt-l2-config.sh"
    "$SCRIPT_DIR/scripts/generate-metadata.sh"
    "$SCRIPT_DIR/scripts/generate-summary.sh"
    "$SCRIPT_DIR/scripts/build-images.sh"
    "$SCRIPT_DIR/scripts/generate-compose.sh"
    "$SCRIPT_DIR/scripts/verify-healthchecks.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ ! -x "$script" ]; then
        log_error "Script not found or not executable: $script"
        exit 1
    fi
done
log "  ✓ All scripts present"

log "Preflight checks passed"

# ============================================================================
# Step 1: Container Discovery
# ============================================================================

log_step "STEP 1: Container Discovery"

DISCOVERY_JSON="$OUTPUT_DIR/discovery.json"

log "Discovering L1 containers for enclave: $ENCLAVE_NAME"

if ! "$SCRIPT_DIR/scripts/discover-containers.sh" "$ENCLAVE_NAME" "$DISCOVERY_JSON" >> "$LOG_FILE" 2>&1; then
    log_error "Container discovery failed"
    log_error "See log file for details: $LOG_FILE"
    exit 1
fi

log "Discovery complete"

# Read and display container info
GETH_CONTAINER=$(jq -r '.geth.container_name' "$DISCOVERY_JSON")
BEACON_CONTAINER=$(jq -r '.beacon.container_name' "$DISCOVERY_JSON")
VALIDATOR_CONTAINER=$(jq -r '.validator.container_name' "$DISCOVERY_JSON")

log "Found containers:"
log "  Geth: $GETH_CONTAINER"
log "  Beacon: $BEACON_CONTAINER"
log "  Validator: $VALIDATOR_CONTAINER"

# ============================================================================
# Step 2: Pre-Stop Metadata Collection
# ============================================================================

log_step "STEP 2: Pre-Stop Metadata Collection"

log "Querying L1 state before stopping..."

# Query current block state via RPC
BLOCK_NUMBER="unknown"
BLOCK_HASH="unknown"
BLOCK_TIMESTAMP="unknown"
GENESIS_HASH="unknown"

if docker ps -q --filter "name=$GETH_CONTAINER" | grep -q .; then
    log "  Querying current block state via RPC..."

    # Get the RPC port from the container
    RPC_PORT=$(docker port "$GETH_CONTAINER" 8545 2>/dev/null | cut -d: -f2 || echo "")

    if [ -n "$RPC_PORT" ]; then
        # Query latest block
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
            fi

            # Extract block hash
            BLOCK_HASH=$(echo "$BLOCK_DATA" | jq -r '.result.hash' 2>/dev/null || echo "unknown")

            # Extract block timestamp (convert hex to decimal)
            BLOCK_TIMESTAMP_HEX=$(echo "$BLOCK_DATA" | jq -r '.result.timestamp' 2>/dev/null || echo "")
            if [ -n "$BLOCK_TIMESTAMP_HEX" ] && [ "$BLOCK_TIMESTAMP_HEX" != "null" ]; then
                BLOCK_TIMESTAMP=$((16#${BLOCK_TIMESTAMP_HEX#0x}))
            fi
        fi

        # Get genesis hash
        GENESIS_DATA=$(curl -s "http://localhost:$RPC_PORT" \
            -X POST \
            -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' \
            2>/dev/null || echo "")

        if [ -n "$GENESIS_DATA" ] && echo "$GENESIS_DATA" | jq -e '.result' &>/dev/null; then
            GENESIS_HASH=$(echo "$GENESIS_DATA" | jq -r '.result.hash' 2>/dev/null || echo "unknown")
        fi

        log "  Current block: $BLOCK_NUMBER"
        log "  Block hash: $BLOCK_HASH"
        log "  Block timestamp: $BLOCK_TIMESTAMP"
        log "  Genesis hash: $GENESIS_HASH"
    else
        log_warn "  Could not find RPC port, falling back to docker exec..."
        # Fallback to docker exec for block number only
        BLOCK_INFO=$(docker exec "$GETH_CONTAINER" sh -c 'geth attach --exec "eth.blockNumber" /data/geth/execution-data/geth.ipc 2>/dev/null' || echo "unknown")
        if [ "$BLOCK_INFO" != "unknown" ]; then
            BLOCK_NUMBER="$BLOCK_INFO"
            log "  Current block: $BLOCK_NUMBER"
        else
            log_warn "  Could not query block number"
        fi
    fi
else
    log_warn "  Geth container not running, skipping live query"
fi

# Save pre-stop state with complete block information
cat > "$OUTPUT_DIR/pre-stop-state.json" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "block_number": "$BLOCK_NUMBER",
    "block_hash": "$BLOCK_HASH",
    "block_timestamp": "$BLOCK_TIMESTAMP",
    "genesis_hash": "$GENESIS_HASH"
}
EOF

log "Pre-stop state saved"

# ============================================================================
# Step 3: State Extraction
# ============================================================================

log_step "STEP 3: State Extraction"

log "Starting state extraction (this will stop containers)..."
log_warn "The L1 will be stopped during this process"

if ! "$SCRIPT_DIR/scripts/extract-state.sh" "$DISCOVERY_JSON" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
    log_error "State extraction failed"
    log_error "See log file for details: $LOG_FILE"
    exit 1
fi

log "State extraction complete"

# ============================================================================
# Step 4: Resume Original Enclave
# ============================================================================

log_step "STEP 4: Resume Original Enclave"

log "Restarting original L1 containers to resume block production..."

# Read container names from discovery JSON
GETH_CONTAINER=$(jq -r '.geth.container_name' "$DISCOVERY_JSON")
BEACON_CONTAINER=$(jq -r '.beacon.container_name' "$DISCOVERY_JSON")
VALIDATOR_CONTAINER=$(jq -r '.validator.container_name' "$DISCOVERY_JSON")

# Restart containers in dependency order: geth -> beacon -> validator
RESTART_SUCCESS=true

log "  Starting Geth..."
if docker start "$GETH_CONTAINER" >> "$LOG_FILE" 2>&1; then
    log "  Geth container restarted: $GETH_CONTAINER"
else
    log_error "  Failed to restart Geth container"
    RESTART_SUCCESS=false
fi

# Wait for Geth to initialize
log "  Waiting for Geth to initialize..."
sleep 5

log "  Starting Beacon..."
if docker start "$BEACON_CONTAINER" >> "$LOG_FILE" 2>&1; then
    log "  Beacon container restarted: $BEACON_CONTAINER"
else
    log_error "  Failed to restart Beacon container"
    RESTART_SUCCESS=false
fi

# Wait for Beacon to connect
log "  Waiting for Beacon to connect..."
sleep 5

log "  Starting Validator..."
if docker start "$VALIDATOR_CONTAINER" >> "$LOG_FILE" 2>&1; then
    log "  Validator container restarted: $VALIDATOR_CONTAINER"
else
    log_error "  Failed to restart Validator container"
    RESTART_SUCCESS=false
fi

if [ "$RESTART_SUCCESS" = true ]; then
    log "All containers restarted successfully"
    log "L1 block production resumed in enclave: $ENCLAVE_NAME"

    # Verify containers are running
    sleep 3
    for container in "$GETH_CONTAINER" "$BEACON_CONTAINER" "$VALIDATOR_CONTAINER"; do
        state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        if [ "$state" = "running" ]; then
            log "  ✓ $container: running"
        else
            log_warn "  ⚠ $container: $state"
        fi
    done
else
    log_warn "Some containers failed to restart"
    log_warn "You may need to restart the enclave manually:"
    log_warn "  kurtosis enclave stop $ENCLAVE_NAME"
    log_warn "  kurtosis enclave start $ENCLAVE_NAME"
fi

# ============================================================================
# Step 5: Metadata Generation
# ============================================================================

log_step "STEP 5: Metadata Generation"

log "Generating metadata and checksums..."

if ! "$SCRIPT_DIR/scripts/generate-metadata.sh" "$DISCOVERY_JSON" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
    log_error "Metadata generation failed"
    log_error "See log file for details: $LOG_FILE"
    exit 1
fi

log "Metadata generation complete"

# ============================================================================
# Step 5.5: Transaction Replay Script Generation
# ============================================================================

log_step "STEP 5.5: Transaction Replay Script Generation"

log "Generating transaction replay script..."

if ! "$SCRIPT_DIR/scripts/generate-replay-script.sh" \
    "$OUTPUT_DIR/artifacts/transactions.jsonl" \
    "$OUTPUT_DIR/artifacts/replay-transactions.sh" >> "$LOG_FILE" 2>&1; then
    log_error "Replay script generation failed"
    log_error "See log file for details: $LOG_FILE"
    exit 1
fi

log "Replay script generated successfully"

# Adapt L2 configurations if present
CHECKPOINT_FILE="$OUTPUT_DIR/metadata/checkpoint.json"
if [ -f "$CHECKPOINT_FILE" ]; then
    log "Adapting L2 configurations..."
    if ! "$SCRIPT_DIR/scripts/adapt-l2-config.sh" "$OUTPUT_DIR" "$DISCOVERY_JSON" "$CHECKPOINT_FILE" >> "$LOG_FILE" 2>&1; then
        log_warn "L2 configuration adaptation failed (non-critical)"
    fi
fi

# Generate summary.json
log "Generating summary.json..."
if ! "$SCRIPT_DIR/scripts/generate-summary.sh" "$DISCOVERY_JSON" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
    log_warn "Summary generation failed (non-critical)"
else
    log "Summary file created: $OUTPUT_DIR/summary.json"
fi

# ============================================================================
# Step 6: Docker Image Build
# ============================================================================

log_step "STEP 6: Docker Image Build"

log "Building Docker images with baked-in state..."
log "This may take several minutes..."

if [ -n "$TAG_SUFFIX" ]; then
    if ! "$SCRIPT_DIR/scripts/build-images.sh" "$DISCOVERY_JSON" "$OUTPUT_DIR" "$TAG_SUFFIX" >> "$LOG_FILE" 2>&1; then
        log_error "Image build failed"
        log_error "See log file for details: $LOG_FILE"
        exit 1
    fi
else
    if ! "$SCRIPT_DIR/scripts/build-images.sh" "$DISCOVERY_JSON" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
        log_error "Image build failed"
        log_error "See log file for details: $LOG_FILE"
        exit 1
    fi
fi

log "Docker images built successfully"

# ============================================================================
# Step 6.5: Update Rollup Config with Actual Replayed Block Hash
# ============================================================================

log_step "STEP 6.5: Update Rollup Config with Replayed Block Hash"

# Check if there are any L2 chains (rollup.json files)
ROLLUP_CONFIGS=$(find "$OUTPUT_DIR/config" -name "rollup.json" 2>/dev/null || true)

if [ -n "$ROLLUP_CONFIGS" ]; then
    log "Found L2 chain configuration(s), querying replayed block hashes..."

    # We need to start geth temporarily to query the replayed chain
    # Get the geth image name from discovery.json
    GETH_IMAGE=$(jq -r '.geth.image' "$DISCOVERY_JSON" 2>/dev/null || echo "snapshot-geth:$TAG")
    GENESIS_FILE="$OUTPUT_DIR/artifacts/genesis.json"

    if [ ! -f "$GENESIS_FILE" ]; then
        log_error "Genesis file not found: $GENESIS_FILE"
        exit 1
    fi

    log "Starting temporary geth container to query replayed chain..."

    # Create a temporary directory for geth data
    TEMP_GETH_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_GETH_DIR" EXIT

    # Copy replay script to scripts directory so it's available when mounted
    # (volume mount shadows the /scripts directory in the image)
    if [ -f "$OUTPUT_DIR/artifacts/replay-transactions.sh" ]; then
        mkdir -p "$OUTPUT_DIR/scripts"
        cp "$OUTPUT_DIR/artifacts/replay-transactions.sh" "$OUTPUT_DIR/scripts/replay-transactions.sh"
        chmod +x "$OUTPUT_DIR/scripts/replay-transactions.sh"
    fi

    # Start geth container in background with manual init and replay
    # We need to execute the same initialization steps as geth-init-entrypoint.sh
    # Note: We skip authrpc setup since we only need HTTP RPC for queries
    TEMP_CONTAINER_ID=$(docker run -d \
        --name "snapshot-temp-geth-$$" \
        --entrypoint "/bin/sh" \
        -v "$GENESIS_FILE:/network-configs/genesis.json:ro" \
        -v "$OUTPUT_DIR/scripts:/scripts:ro" \
        -p 18545:8545 \
        "$GETH_IMAGE" \
        -c 'if [ ! -d "/data/geth/execution-data/geth" ]; then geth init --datadir=/data/geth/execution-data /network-configs/genesis.json; fi && geth --http --http.addr=0.0.0.0 --http.port=8545 --http.vhosts="*" --http.corsdomain="*" --http.api=admin,net,eth,web3,debug,txpool --datadir=/data/geth/execution-data --port=30303 --discovery.port=30303 --syncmode=full --gcmode=archive --networkid=271828 --allow-insecure-unlock --nodiscover & until wget -q -O - http://localhost:8545 > /dev/null 2>&1; do sleep 1; done && /scripts/replay-transactions.sh && tail -f /dev/null' 2>> "$LOG_FILE")

    if [ -z "$TEMP_CONTAINER_ID" ]; then
        log_error "Failed to start temporary geth container"
        exit 1
    fi

    log "  Container started: $TEMP_CONTAINER_ID"
    log "  Waiting for transaction replay to complete..."

    # Wait for replay to complete (check for .replay_complete marker)
    RETRY_COUNT=0
    MAX_RETRIES=120  # 10 minutes timeout

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if docker exec "$TEMP_CONTAINER_ID" test -f /data/geth/.replay_complete 2>/dev/null; then
            log "  ✓ Transaction replay complete"
            break
        fi

        # Check if container is still running
        if ! docker ps -q --filter "id=$TEMP_CONTAINER_ID" | grep -q .; then
            log_error "Temporary geth container stopped unexpectedly"
            docker logs "$TEMP_CONTAINER_ID" >> "$LOG_FILE" 2>&1
            docker rm -f "$TEMP_CONTAINER_ID" >> "$LOG_FILE" 2>&1
            exit 1
        fi

        sleep 5
        RETRY_COUNT=$((RETRY_COUNT + 1))

        if [ $((RETRY_COUNT % 12)) -eq 0 ]; then
            log "  Still waiting... (${RETRY_COUNT}/${MAX_RETRIES})"
        fi
    done

    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        log_error "Timeout waiting for transaction replay to complete"
        docker logs "$TEMP_CONTAINER_ID" >> "$LOG_FILE" 2>&1
        docker rm -f "$TEMP_CONTAINER_ID" >> "$LOG_FILE" 2>&1
        exit 1
    fi

    # Wait a bit more for RPC to be ready
    log "  Waiting for geth RPC to be ready..."
    sleep 5

    # Now query the actual block hash for each rollup config
    for ROLLUP_CONFIG in $ROLLUP_CONFIGS; do
        log "  Processing: $ROLLUP_CONFIG"

        # Extract the L1 genesis block number from rollup.json
        L1_GENESIS_BLOCK=$(jq -r '.genesis.l1.number' "$ROLLUP_CONFIG" 2>/dev/null)

        if [ -z "$L1_GENESIS_BLOCK" ] || [ "$L1_GENESIS_BLOCK" = "null" ]; then
            log "    WARNING: Could not extract L1 genesis block number, skipping"
            continue
        fi

        log "    L1 genesis block number: $L1_GENESIS_BLOCK"

        # Query the actual block hash from the replayed chain
        BLOCK_NUM_HEX=$(printf "0x%x" "$L1_GENESIS_BLOCK")
        log "    Querying block hash for block $L1_GENESIS_BLOCK ($BLOCK_NUM_HEX)..."

        ACTUAL_HASH=$(docker exec "$TEMP_CONTAINER_ID" wget -q -O - \
            --post-data="{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUM_HEX\",false],\"id\":1}" \
            --header='Content-Type:application/json' \
            http://localhost:8545 2>/dev/null | \
            jq -r '.result.hash' 2>/dev/null)

        if [ -z "$ACTUAL_HASH" ] || [ "$ACTUAL_HASH" = "null" ]; then
            log "    WARNING: Block $L1_GENESIS_BLOCK not found in replayed chain"
            log "    Falling back to latest block..."

            # Query the latest block number
            LATEST_BLOCK_HEX=$(docker exec "$TEMP_CONTAINER_ID" wget -q -O - \
                --post-data='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                --header='Content-Type:application/json' \
                http://localhost:8545 2>/dev/null | \
                jq -r '.result' 2>/dev/null)

            LATEST_BLOCK_DEC=$(printf "%d" "$LATEST_BLOCK_HEX" 2>/dev/null || echo "0")
            log "    Latest block in replayed chain: $LATEST_BLOCK_DEC"

            # Query the hash of the latest block
            ACTUAL_HASH=$(docker exec "$TEMP_CONTAINER_ID" wget -q -O - \
                --post-data="{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$LATEST_BLOCK_HEX\",false],\"id\":1}" \
                --header='Content-Type:application/json' \
                http://localhost:8545 2>/dev/null | \
                jq -r '.result.hash' 2>/dev/null)

            # Update the block number in rollup.json as well
            L1_GENESIS_BLOCK="$LATEST_BLOCK_DEC"
            BLOCK_NUM_HEX="$LATEST_BLOCK_HEX"
        fi

        if [ -z "$ACTUAL_HASH" ] || [ "$ACTUAL_HASH" = "null" ]; then
            log_error "Failed to query block hash from replayed chain"
            docker logs "$TEMP_CONTAINER_ID" >> "$LOG_FILE" 2>&1
            docker rm -f "$TEMP_CONTAINER_ID" >> "$LOG_FILE" 2>&1
            exit 1
        fi

        log "    Actual replayed hash: $ACTUAL_HASH (block $L1_GENESIS_BLOCK)"

        # Update the rollup.json with the actual hash and block number
        OLD_HASH=$(jq -r '.genesis.l1.hash' "$ROLLUP_CONFIG" 2>/dev/null)
        OLD_NUMBER=$(jq -r '.genesis.l1.number' "$ROLLUP_CONFIG" 2>/dev/null)
        log "    Original: hash=$OLD_HASH, number=$OLD_NUMBER"

        if [ "$OLD_HASH" != "$ACTUAL_HASH" ] || [ "$OLD_NUMBER" != "$L1_GENESIS_BLOCK" ]; then
            log "    Updating rollup.json with actual replayed values..."
            jq ".genesis.l1.hash = \"$ACTUAL_HASH\" | .genesis.l1.number = $L1_GENESIS_BLOCK" "$ROLLUP_CONFIG" > "$ROLLUP_CONFIG.tmp" && \
                mv "$ROLLUP_CONFIG.tmp" "$ROLLUP_CONFIG" && \
                log "    ✓ Updated rollup.json" || \
                log "    WARNING: Failed to update rollup.json"
        else
            log "    ✓ Values already match (no update needed)"
        fi
    done

    # Clean up temporary container
    log "  Cleaning up temporary geth container..."
    docker rm -f "$TEMP_CONTAINER_ID" >> "$LOG_FILE" 2>&1
    log "  ✓ Cleanup complete"
else
    log "No L2 chain configurations found, skipping block hash update"
fi

# ============================================================================
# Step 7: Docker Compose Generation
# ============================================================================

log_step "STEP 7: Docker Compose Generation"

log "Generating Docker Compose configuration..."

if ! "$SCRIPT_DIR/scripts/generate-compose.sh" "$DISCOVERY_JSON" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
    log_error "Compose generation failed"
    log_error "See log file for details: $LOG_FILE"
    exit 1
fi

log "Docker Compose generation complete"

# Verify healthchecks are properly configured
log "Verifying healthcheck configurations..."

if ! "$SCRIPT_DIR/scripts/verify-healthchecks.sh" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
    log_error "Healthcheck verification failed"
    log_error "See log file for details: $LOG_FILE"
    exit 1
fi

log "Healthcheck verification passed"

# ============================================================================
# Step 8: Finalization
# ============================================================================

log_step "STEP 8: Finalization"

log "Finalizing snapshot..."

# Create snapshot summary (this file will be cleaned up later)
TAG=$(cat "$OUTPUT_DIR/images/.tag" 2>/dev/null || echo "unknown")

log "Snapshot finalization in progress..."

# ============================================================================
# Step 9: Verification
# ============================================================================

VERIFY_SUCCESS=false

if [ "$SKIP_VERIFY" = true ]; then
    log_step "STEP 9: Snapshot Verification (SKIPPED)"
    log "Verification skipped per --skip-verify flag"
    log "You can manually verify later using:"
    log "  $SCRIPT_DIR/verify.sh $OUTPUT_DIR"
    log ""
    VERIFY_SUCCESS="skipped"
else
    log_step "STEP 9: Snapshot Verification"

    log "Running automated verification tests..."
    log "This will:"
    log "  - Start the snapshot containers"
    log "  - Verify initial block state matches checkpoint"
    log "  - Wait for blocks to progress"
    log "  - Check all services are healthy"
    log ""
    log_info "This may take 1-2 minutes..."
    log ""

    # Run verify.sh and capture output
    if "$SCRIPT_DIR/verify.sh" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
        VERIFY_SUCCESS=true
        log "✓ Snapshot verification PASSED"
        log "  All tests completed successfully"
    else
        log_error "✗ Snapshot verification FAILED"
        log_error "  Some tests did not pass - check log for details"
    fi

    log ""
    log "Verification details: $LOG_FILE"
fi

# ============================================================================
# Step 10: Cleanup Unnecessary Files
# ============================================================================

log_step "STEP 10: Cleanup"

log "Removing temporary and intermediate files..."

# Note: DO NOT remove these directories - they contain files needed at runtime:
#  artifacts/ - genesis.json, jwt.hex, genesis.ssz, replay-transactions.sh, validator-keys
#  metadata/ - checkpoint.json (needed by verify.sh)

# Remove build directories that are no longer needed
rm -rf "$OUTPUT_DIR/datadirs" 2>/dev/null || true
rm -rf "$OUTPUT_DIR/images" 2>/dev/null || true

# Remove individual files that are no longer needed
rm -f "$OUTPUT_DIR/discovery.json" 2>/dev/null || true
rm -f "$OUTPUT_DIR/pre-stop-state.json" 2>/dev/null || true
rm -f "$OUTPUT_DIR/query-state.sh" 2>/dev/null || true
rm -f "$OUTPUT_DIR/SNAPSHOT_INFO.txt" 2>/dev/null || true
rm -f "$OUTPUT_DIR/SNAPSHOT_SUMMARY.txt" 2>/dev/null || true
rm -f "$OUTPUT_DIR/start-snapshot.sh" 2>/dev/null || true
rm -f "$OUTPUT_DIR/stop-snapshot.sh" 2>/dev/null || true
rm -f "$OUTPUT_DIR/USAGE.md" 2>/dev/null || true
rm -f "$OUTPUT_DIR/snapshot.log" 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.bak 2>/dev/null || true

log "Cleanup complete - snapshot is ready for distribution"

# ============================================================================
# Success
# ============================================================================

if [ "$VERIFY_SUCCESS" = true ]; then
    log_step "✓ SNAPSHOT COMPLETE AND VERIFIED!"
elif [ "$VERIFY_SUCCESS" = "skipped" ]; then
    log_step "✓ SNAPSHOT COMPLETE (Verification Skipped)"
else
    log_step "⚠ SNAPSHOT COMPLETE (Verification Issues Detected)"
fi

echo ""
log "Snapshot: $SNAPSHOT_NAME"
log "Output directory: $OUTPUT_DIR"
log ""
log "Docker images created:"
log "  - snapshot-geth:$TAG"
log "  - snapshot-beacon:$TAG"
log "  - snapshot-validator:$TAG"
log ""
log "Original enclave status:"
log "  Enclave '$ENCLAVE_NAME' L1 block production has been resumed"
log "  Containers: $GETH_CONTAINER, $BEACON_CONTAINER, $VALIDATOR_CONTAINER"
log ""

if [ "$VERIFY_SUCCESS" = true ]; then
    log "Verification: ✓ PASSED"
    log "The snapshot has been tested and is working correctly"
    log ""
    log "Quick start:"
    log "  cd $OUTPUT_DIR"
    log "  docker-compose up -d"
    log ""
    log "View network details:"
    log "  cat $OUTPUT_DIR/summary.json | jq"
    EXIT_CODE=0
elif [ "$VERIFY_SUCCESS" = "skipped" ]; then
    log_warn "Verification: SKIPPED"
    log "The snapshot was created but verification was skipped"
    log "To verify manually, run:"
    log "  $SCRIPT_DIR/verify.sh $OUTPUT_DIR"
    log ""
    log "Quick start:"
    log "  cd $OUTPUT_DIR"
    log "  docker-compose up -d"
    log ""
    log "View network details:"
    log "  cat $OUTPUT_DIR/summary.json | jq"
    EXIT_CODE=0
else
    log_warn "Verification: ✗ FAILED"
    log_warn "The snapshot was created but verification tests failed"
    log_warn "Review the logs to diagnose issues"
    log ""
    log "Troubleshooting:"
    log "  1. Check logs: tail -100 $LOG_FILE"
    log "  2. Manual test: cd $OUTPUT_DIR && docker-compose up -d"
    log "  3. Check services: cd $OUTPUT_DIR && docker-compose ps"
    EXIT_CODE=1
fi

log ""
log "Full log: $LOG_FILE"

exit $EXIT_CODE
