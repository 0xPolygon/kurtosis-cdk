#!/usr/bin/env bash
#
# Docker Image Builder Script
# Builds Docker images with L1 state baked in
#
# Usage: build-images.sh <DISCOVERY_JSON> <OUTPUT_DIR> [TAG_SUFFIX]
#

set -euo pipefail

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <DISCOVERY_JSON> <OUTPUT_DIR> [TAG_SUFFIX]" >&2
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
GETH_IMAGE=$(jq -r '.geth.image' "$DISCOVERY_JSON")
BEACON_IMAGE=$(jq -r '.beacon.image' "$DISCOVERY_JSON")
VALIDATOR_IMAGE=$(jq -r '.validator.image' "$DISCOVERY_JSON")

# Generate tag
TIMESTAMP=$(date -u +'%Y%m%d-%H%M%S')
if [ -n "$TAG_SUFFIX" ]; then
    TAG="${ENCLAVE_NAME}-${TIMESTAMP}-${TAG_SUFFIX}"
else
    TAG="${ENCLAVE_NAME}-${TIMESTAMP}"
fi

log "Image tag: $TAG"

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
ELECTRA_FORK_EPOCH: 18446744073709551615

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
FROM consensys/teku:24.12.0

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
FROM consensys/teku:24.12.0

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
