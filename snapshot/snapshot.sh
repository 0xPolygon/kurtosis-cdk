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
  -h, --help          Show this help message

Examples:
  # Basic snapshot
  $0 snapshot-test

  # Custom output directory
  $0 snapshot-test --out ./my-snapshots

  # With custom tag
  $0 snapshot-test --tag v1.0.0

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
    "$SCRIPT_DIR/scripts/build-images.sh"
    "$SCRIPT_DIR/scripts/generate-compose.sh"
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

# Adapt L2 configurations if present
CHECKPOINT_FILE="$OUTPUT_DIR/metadata/checkpoint.json"
if [ -f "$CHECKPOINT_FILE" ]; then
    log "Adapting L2 configurations..."
    if ! "$SCRIPT_DIR/scripts/adapt-l2-config.sh" "$OUTPUT_DIR" "$DISCOVERY_JSON" "$CHECKPOINT_FILE" >> "$LOG_FILE" 2>&1; then
        log_warn "L2 configuration adaptation failed (non-critical)"
    fi
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

# ============================================================================
# Step 8: Finalization
# ============================================================================

log_step "STEP 8: Finalization"

log "Finalizing snapshot..."

# Create snapshot summary
TAG=$(cat "$OUTPUT_DIR/images/.tag" 2>/dev/null || echo "unknown")

cat > "$OUTPUT_DIR/SNAPSHOT_SUMMARY.txt" << EOF
Ethereum L1 Snapshot Summary
============================

Snapshot Name: $SNAPSHOT_NAME
Created: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Enclave: $ENCLAVE_NAME

Components
----------
Geth: $GETH_CONTAINER
Beacon: $BEACON_CONTAINER
Validator: $VALIDATOR_CONTAINER

Images
------
snapshot-geth:$TAG
snapshot-beacon:$TAG
snapshot-validator:$TAG

State
-----
Pre-stop block: $BLOCK_NUMBER

Original Enclave
----------------
Status: Resumed and producing blocks
Enclave: $ENCLAVE_NAME
Containers:
  - $GETH_CONTAINER
  - $BEACON_CONTAINER
  - $VALIDATOR_CONTAINER

Files Generated
---------------
$(find "$OUTPUT_DIR" -type f | wc -l) files
Total size: $(du -sh "$OUTPUT_DIR" | cut -f1)

Quick Start
-----------
To start this snapshot:
  cd $OUTPUT_DIR
  ./start-snapshot.sh

To verify this snapshot:
  $SCRIPT_DIR/verify.sh $OUTPUT_DIR

For detailed usage:
  cat $OUTPUT_DIR/USAGE.md

EOF

log "Snapshot summary created"

# ============================================================================
# Step 9: Verification
# ============================================================================

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
VERIFY_SUCCESS=false
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

# ============================================================================
# Success
# ============================================================================

if [ "$VERIFY_SUCCESS" = true ]; then
    log_step "✓ SNAPSHOT COMPLETE AND VERIFIED!"
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
    log "  ./start-snapshot.sh"
    log ""
    log "For details:"
    log "  cat $OUTPUT_DIR/SNAPSHOT_SUMMARY.txt"
    EXIT_CODE=0
else
    log_warn "Verification: ✗ FAILED"
    log_warn "The snapshot was created but verification tests failed"
    log_warn "Review the logs to diagnose issues"
    log ""
    log "Troubleshooting:"
    log "  1. Check logs: tail -100 $LOG_FILE"
    log "  2. Manual test: cd $OUTPUT_DIR && ./start-snapshot.sh"
    log "  3. Check services: cd $OUTPUT_DIR && docker-compose ps"
    EXIT_CODE=1
fi

log ""
log "Full log: $LOG_FILE"

exit $EXIT_CODE
