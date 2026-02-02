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

# Copy datadir tarball
cp "$OUTPUT_DIR/datadirs/lighthouse_beacon.tar" "$BEACON_BUILD_DIR/"

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

# Create Dockerfile
cat > "$BEACON_BUILD_DIR/Dockerfile" << 'EOF'
FROM sigp/lighthouse:v8.0.1

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy beacon datadir
COPY lighthouse_beacon.tar /tmp/lighthouse_beacon.tar

# Copy artifacts (may be empty files if not available)
COPY chain-spec.yaml /tmp/chain-spec.yaml
COPY jwt.hex /tmp/jwt.hex

# Extract datadir
RUN mkdir -p /data/lighthouse && \
    cd /data/lighthouse && \
    tar -xzf /tmp/lighthouse_beacon.tar && \
    rm /tmp/lighthouse_beacon.tar

# Copy artifacts if they have content and create testnet directory
RUN mkdir -p /network-configs /jwt && \
    if [ -s /tmp/chain-spec.yaml ]; then \
        cp /tmp/chain-spec.yaml /network-configs/config.yaml; \
    fi && \
    if [ -s /tmp/jwt.hex ]; then \
        cp /tmp/jwt.hex /jwt/jwtsecret; \
    fi && \
    echo "0" > /network-configs/deploy_block.txt && \
    echo "0" > /network-configs/deposit_contract_block.txt && \
    echo "[]" > /network-configs/boot_enr.yaml && \
    rm -f /tmp/chain-spec.yaml /tmp/jwt.hex

# Set working directory
WORKDIR /data/lighthouse

# Ensure data is accessible
RUN chmod -R 755 /data/lighthouse

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

# Ensure slashing protection database exists
RUN test -f /validator-keys/keys/slashing_protection.sqlite || \
    (echo "ERROR: slashing_protection.sqlite not found" && exit 1)

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
log "  snapshot-geth:$TAG ($(docker images --format "{{.Size}}" snapshot-geth:$TAG))"
log "  snapshot-beacon:$TAG ($(docker images --format "{{.Size}}" snapshot-beacon:$TAG))"
log "  snapshot-validator:$TAG ($(docker images --format "{{.Size}}" snapshot-validator:$TAG))"
log ""
log "To verify images:"
log "  docker images | grep snapshot-"

# Write tag file for compose generation
echo "$TAG" > "$OUTPUT_DIR/images/.tag"

exit 0
