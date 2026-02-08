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
mkdir -p "$OUTPUT_DIR/images"/{replayer,geth,beacon,validator}

# ============================================================================
# Build Transaction Replayer Image
# ============================================================================

log "Building transaction replayer image..."

REPLAYER_BUILD_DIR="$OUTPUT_DIR/images/replayer"

# Copy replay script
if [ ! -f "$OUTPUT_DIR/artifacts/replay-transactions.sh" ]; then
    log "ERROR: Replay script not found: $OUTPUT_DIR/artifacts/replay-transactions.sh"
    exit 1
fi

cp "$OUTPUT_DIR/artifacts/replay-transactions.sh" "$REPLAYER_BUILD_DIR/"

# Create Dockerfile
cat > "$REPLAYER_BUILD_DIR/Dockerfile" << 'EOF'
FROM alpine:3.19

# Install dependencies
RUN apk add --no-cache bash wget

# Copy replay script
COPY replay-transactions.sh /replay-transactions.sh
RUN chmod +x /replay-transactions.sh

# Default command
CMD ["/replay-transactions.sh"]
EOF

log "  Building snapshot-replayer:$TAG..."
docker build -t "snapshot-replayer:$TAG" "$REPLAYER_BUILD_DIR"

if docker images -q "snapshot-replayer:$TAG" &> /dev/null; then
    log "  Replayer image built successfully"
    docker tag "snapshot-replayer:$TAG" "snapshot-replayer:latest"
else
    log "ERROR: Failed to build Replayer image"
    exit 1
fi

# ============================================================================
# Build Geth Image (Fresh Start with Genesis)
# ============================================================================

log "Building Geth execution layer image..."

GETH_BUILD_DIR="$OUTPUT_DIR/images/geth"

# Copy genesis.json
if [ ! -f "$OUTPUT_DIR/artifacts/genesis.json" ]; then
    log "ERROR: genesis.json not found"
    exit 1
fi

cp "$OUTPUT_DIR/artifacts/genesis.json" "$GETH_BUILD_DIR/"

# Copy JWT secret
if [ -f "$OUTPUT_DIR/artifacts/jwt.hex" ]; then
    cp "$OUTPUT_DIR/artifacts/jwt.hex" "$GETH_BUILD_DIR/jwtsecret"
else
    log "ERROR: JWT secret not found"
    exit 1
fi

# Create geth init entrypoint
cat > "$GETH_BUILD_DIR/geth-init-entrypoint.sh" << 'EOFENTRY'
#!/bin/sh
set -e

echo "Initializing geth with genesis..."

# Create data directory
mkdir -p /data/geth/execution-data

# Initialize genesis if not already done
if [ ! -d "/data/geth/execution-data/geth" ]; then
    echo "Running geth init..."
    geth init --datadir /data/geth/execution-data /network-configs/genesis.json
    echo "Genesis initialized"
else
    echo "Genesis already initialized, skipping init"
fi

echo "Starting geth..."
exec geth "$@"
EOFENTRY

chmod +x "$GETH_BUILD_DIR/geth-init-entrypoint.sh"

# Create Dockerfile
cat > "$GETH_BUILD_DIR/Dockerfile" << 'EOF'
FROM ethereum/client-go:v1.16.8

# Copy genesis and JWT
COPY genesis.json /network-configs/genesis.json
COPY jwtsecret /jwt/jwtsecret

# Copy init entrypoint
COPY geth-init-entrypoint.sh /geth-init-entrypoint.sh

# Set permissions
RUN chmod 644 /jwt/jwtsecret && \
    chmod +x /geth-init-entrypoint.sh

# Set working directory
WORKDIR /data/geth

# Use init entrypoint
ENTRYPOINT ["/geth-init-entrypoint.sh"]

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
# Regenerate Genesis with Fresh Timestamp
# ============================================================================

log "Regenerating genesis.ssz with fresh timestamp..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -x "$SCRIPT_DIR/generate-fresh-genesis.sh" ]; then
    if "$SCRIPT_DIR/generate-fresh-genesis.sh" "$OUTPUT_DIR" >> "$LOG_FILE" 2>&1; then
        log "  ✓ Fresh genesis.ssz generated successfully"
    else
        log "  WARNING: Genesis regeneration failed, using original genesis.ssz"
        log "  Snapshot will have ~30 minute time window limitation"
    fi
else
    log "  WARNING: generate-fresh-genesis.sh not found, using original genesis.ssz"
fi

# ============================================================================
# Build Lighthouse Beacon Image (Fresh Start)
# ============================================================================

log "Building Lighthouse beacon node image..."

BEACON_BUILD_DIR="$OUTPUT_DIR/images/beacon"

# Copy genesis.ssz (either fresh or original)
if [ ! -f "$OUTPUT_DIR/artifacts/genesis.ssz" ]; then
    log "ERROR: genesis.ssz not found"
    exit 1
fi

cp "$OUTPUT_DIR/artifacts/genesis.ssz" "$BEACON_BUILD_DIR/"

# Copy and modify chain spec to set fresh genesis time
if [ -f "$OUTPUT_DIR/artifacts/chain-spec.yaml" ]; then
    # Calculate new genesis time: now + 30 seconds
    NEW_GENESIS_TIME=$(($(date +%s) + 30))

    log "  Setting genesis time to: $NEW_GENESIS_TIME ($(date -d @$NEW_GENESIS_TIME))"

    # Update MIN_GENESIS_TIME in the config
    sed "s/^MIN_GENESIS_TIME: .*/MIN_GENESIS_TIME: $NEW_GENESIS_TIME/" \
        "$OUTPUT_DIR/artifacts/chain-spec.yaml" > "$BEACON_BUILD_DIR/chain-spec.yaml"

    # Also update GENESIS_DELAY if present
    sed -i "s/^GENESIS_DELAY: .*/GENESIS_DELAY: 30/" "$BEACON_BUILD_DIR/chain-spec.yaml"

    log "  ✓ Chain spec updated with fresh genesis time"
else
    touch "$BEACON_BUILD_DIR/chain-spec.yaml"
    log "  WARNING: chain-spec.yaml not found, using empty config"
fi

# Copy JWT secret
if [ -f "$OUTPUT_DIR/artifacts/jwt.hex" ]; then
    cp "$OUTPUT_DIR/artifacts/jwt.hex" "$BEACON_BUILD_DIR/"
else
    log "ERROR: JWT secret not found"
    exit 1
fi

# Create beacon init script
cat > "$BEACON_BUILD_DIR/beacon-init.sh" << 'EOFBEACON'
#!/bin/sh
set -e

echo "Setting up beacon node..."

# Create directories
mkdir -p /data/lighthouse/beacon-data
mkdir -p /network-configs
mkdir -p /jwt

# Copy genesis.ssz to network-configs
if [ -f /data/metadata/genesis.ssz ]; then
    cp /data/metadata/genesis.ssz /network-configs/genesis.ssz
    echo "Genesis.ssz copied to /network-configs/"
else
    echo "WARNING: genesis.ssz not found at /data/metadata/genesis.ssz"
fi

# Copy chain spec if available
if [ -f /data/metadata/config.yaml ]; then
    cp /data/metadata/config.yaml /network-configs/config.yaml
fi

# Copy JWT
if [ -f /data/metadata/jwtsecret ]; then
    cp /data/metadata/jwtsecret /jwt/jwtsecret
fi

# Create empty boot_enr and deployment files
echo "[]" > /network-configs/boot_enr.yaml
echo "0" > /network-configs/deploy_block.txt
echo "0" > /network-configs/deposit_contract_block.txt

echo "Beacon initialization complete"
echo "Starting beacon node..."
exec "$@"
EOFBEACON

chmod +x "$BEACON_BUILD_DIR/beacon-init.sh"

# Create Dockerfile
cat > "$BEACON_BUILD_DIR/Dockerfile" << 'EOF'
FROM sigp/lighthouse:v8.0.1

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy genesis and config files
COPY genesis.ssz /data/metadata/genesis.ssz
COPY chain-spec.yaml /data/metadata/config.yaml
COPY jwt.hex /data/metadata/jwtsecret

# Copy init script
COPY beacon-init.sh /beacon-init.sh

# Set permissions
RUN chmod 644 /data/metadata/* && \
    chmod +x /beacon-init.sh

# Set working directory
WORKDIR /data/lighthouse

# Use init entrypoint
ENTRYPOINT ["/beacon-init.sh"]

# Default command (will be overridden by docker-compose)
CMD ["lighthouse", "beacon_node"]
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

# Create Dockerfile
cat > "$VALIDATOR_BUILD_DIR/Dockerfile" << 'EOF'
FROM sigp/lighthouse:v8.0.1

# Copy validator datadir
COPY lighthouse_validator.tar /tmp/lighthouse_validator.tar

# Copy chain-spec
COPY chain-spec.yaml /tmp/chain-spec.yaml

# Extract datadir and keep validator-keys structure intact
RUN mkdir -p /validator-keys && \
    cd / && \
    tar -xzf /tmp/lighthouse_validator.tar && \
    cp -r validator-data/validator-keys/* /validator-keys/ && \
    rm -rf validator-data && \
    rm /tmp/lighthouse_validator.tar

# Ensure secrets directory has password files
# The secrets directory may be empty due to permission issues during extraction
# so we copy from lodestar-secrets which contains the same base64-encoded passwords
RUN if [ ! "$(ls -A /validator-keys/secrets 2>/dev/null)" ]; then \
        echo "Secrets directory empty, copying from lodestar-secrets..." && \
        cp -r /validator-keys/lodestar-secrets/* /validator-keys/secrets/ 2>/dev/null || \
        (echo "ERROR: Could not populate secrets directory" && exit 1); \
    fi

# Verify keys and secrets directories have content
RUN test -d /validator-keys/keys || (echo "ERROR: keys directory not found" && exit 1) && \
    test "$(ls -A /validator-keys/secrets 2>/dev/null)" || (echo "ERROR: secrets directory is empty" && exit 1)

# Create testnet directory with config files
RUN mkdir -p /network-configs && \
    if [ -s /tmp/chain-spec.yaml ]; then \
        cp /tmp/chain-spec.yaml /network-configs/config.yaml; \
    fi && \
    echo "0" > /network-configs/deploy_block.txt && \
    echo "0" > /network-configs/deposit_contract_block.txt && \
    echo "[]" > /network-configs/boot_enr.yaml && \
    rm -f /tmp/chain-spec.yaml

# Remove slashing protection database - will be recreated fresh on startup
# This prevents "NewSurroundsPrev" slashing errors when restarting from genesis
RUN rm -f /validator-keys/keys/slashing_protection.sqlite && \
    echo "Slashing protection database removed for fresh snapshot" && \
    echo "Lighthouse will create a fresh DB on startup with --init-slashing-protection"

# Set permissions
RUN chmod -R 755 /validator-keys

# Default command (will be overridden by docker-compose)
CMD ["lighthouse", "validator_client"]
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
    "replayer": {
      "name": "snapshot-replayer:$TAG",
      "base_image": "alpine:3.19",
      "size": "$(docker images --format "{{.Size}}" snapshot-replayer:$TAG)"
    },
    "geth": {
      "name": "snapshot-geth:$TAG",
      "base_image": "$GETH_IMAGE",
      "size": "$(docker images --format "{{.Size}}" snapshot-geth:$TAG)"
    },
    "beacon": {
      "name": "snapshot-beacon:$TAG",
      "base_image": "$BEACON_IMAGE",
      "size": "$(docker images --format "{{.Size}}" snapshot-beacon:$TAG)"
    },
    "validator": {
      "name": "snapshot-validator:$TAG",
      "base_image": "$VALIDATOR_IMAGE",
      "size": "$(docker images --format "{{.Size}}" snapshot-validator:$TAG)"
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
log "  snapshot-replayer:$TAG ($(docker images --format "{{.Size}}" snapshot-replayer:$TAG))"
log "  snapshot-geth:$TAG ($(docker images --format "{{.Size}}" snapshot-geth:$TAG))"
log "  snapshot-beacon:$TAG ($(docker images --format "{{.Size}}" snapshot-beacon:$TAG))"
log "  snapshot-validator:$TAG ($(docker images --format "{{.Size}}" snapshot-validator:$TAG))"
log ""
log "To verify images:"
log "  docker images | grep snapshot-"

# Write tag file for compose generation
echo "$TAG" > "$OUTPUT_DIR/images/.tag"

exit 0
