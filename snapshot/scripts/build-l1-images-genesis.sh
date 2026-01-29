#!/bin/bash
# Build L1 Docker images from genesis file (simplified standalone script)
#
# This script builds Docker images for geth and lighthouse using a genesis-based
# approach where all L1 state is pre-loaded in the genesis file.

set -euo pipefail

# Default values
OUTPUT_DIR=""
GETH_BASE_IMAGE="ethereum/client-go:v1.16.8"
LIGHTHOUSE_BASE_IMAGE="sigp/lighthouse:v8.0.1"
GETH_TAG="l1-geth:snapshot"
LIGHTHOUSE_TAG="l1-lighthouse:snapshot"
GETH_SERVICE_NAME="l1-geth"
LOG_FORMAT="json"

# Print usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build L1 Docker images from genesis file for snapshot.

Options:
    --output-dir DIR          Output directory containing genesis (required)
    --geth-image IMAGE        Geth base image (default: ethereum/client-go:v1.16.8)
    --lighthouse-image IMAGE  Lighthouse base image (default: sigp/lighthouse:v8.0.1)
    --geth-tag TAG            Tag for built geth image (default: l1-geth:snapshot)
    --lighthouse-tag TAG      Tag for built lighthouse image (default: l1-lighthouse:snapshot)
    --geth-service-name NAME  Docker-compose service name for geth (default: l1-geth)
    --log-format FORMAT       Log format: json or terminal (default: json)
    -h, --help                Show this help message

Example:
    $0 --output-dir ./snapshot-output

EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --geth-image)
            GETH_BASE_IMAGE="$2"
            shift 2
            ;;
        --lighthouse-image)
            LIGHTHOUSE_BASE_IMAGE="$2"
            shift 2
            ;;
        --geth-tag)
            GETH_TAG="$2"
            shift 2
            ;;
        --lighthouse-tag)
            LIGHTHOUSE_TAG="$2"
            shift 2
            ;;
        --geth-service-name)
            GETH_SERVICE_NAME="$2"
            shift 2
            ;;
        --log-format)
            LOG_FORMAT="$2"
            if [[ "${LOG_FORMAT}" != "json" && "${LOG_FORMAT}" != "terminal" ]]; then
                echo "Error: --log-format must be 'json' or 'terminal'" >&2
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "${OUTPUT_DIR}" ]; then
    echo "Error: --output-dir is required" >&2
    usage
fi

if [ ! -d "${OUTPUT_DIR}" ]; then
    echo "Error: Output directory does not exist: ${OUTPUT_DIR}" >&2
    exit 1
fi

# Check required files
GENESIS_FILE="${OUTPUT_DIR}/l1-state/genesis.json"
LIGHTHOUSE_TESTNET_DIR="${OUTPUT_DIR}/l1-state/lighthouse-testnet"
VALIDATOR_KEYS_DIR="${OUTPUT_DIR}/l1-state/validator-keys"

if [ ! -f "${GENESIS_FILE}" ]; then
    echo "Error: Genesis file not found: ${GENESIS_FILE}" >&2
    echo "Hint: Run extract-l1-state.sh first" >&2
    exit 1
fi

if [ ! -d "${LIGHTHOUSE_TESTNET_DIR}" ]; then
    echo "Error: Lighthouse testnet config not found: ${LIGHTHOUSE_TESTNET_DIR}" >&2
    exit 1
fi

# Read chain ID from genesis
CHAIN_ID=$(jq -r '.config.chainId // 271828' "${GENESIS_FILE}" 2>/dev/null || echo "271828")

echo "=== L1 Docker Image Build (Genesis-based) ==="
echo ""
echo "Configuration:"
echo "  Output directory: ${OUTPUT_DIR}"
echo "  Genesis file: ${GENESIS_FILE}"
echo "  Chain ID: ${CHAIN_ID}"
echo "  Geth image: ${GETH_TAG} (base: ${GETH_BASE_IMAGE})"
echo "  Lighthouse image: ${LIGHTHOUSE_TAG} (base: ${LIGHTHOUSE_BASE_IMAGE})"
echo "  Log format: ${LOG_FORMAT}"
echo ""

# Prepare directories
DOCKERFILES_DIR="${OUTPUT_DIR}/dockerfiles"
GETH_BUILD_DIR="${DOCKERFILES_DIR}/geth-build-context"
LIGHTHOUSE_BUILD_DIR="${DOCKERFILES_DIR}/lighthouse-build-context"

mkdir -p "${DOCKERFILES_DIR}"
mkdir -p "${GETH_BUILD_DIR}"
mkdir -p "${LIGHTHOUSE_BUILD_DIR}"

# ========================================
# Prepare Geth Build Context
# ========================================
echo "Preparing geth build context..."

# Copy genesis file
cp "${GENESIS_FILE}" "${GETH_BUILD_DIR}/genesis.json"

# Generate or copy JWT secret
JWT_SECRET_SOURCE="${OUTPUT_DIR}/l1-state/jwtsecret"
if [ ! -f "${JWT_SECRET_SOURCE}" ]; then
    echo "Generating JWT secret..."
    openssl rand -hex 32 > "${JWT_SECRET_SOURCE}"
fi
cp "${JWT_SECRET_SOURCE}" "${GETH_BUILD_DIR}/jwtsecret"
chmod 600 "${GETH_BUILD_DIR}/jwtsecret"

echo "✅ Geth build context ready"

# ========================================
# Prepare Lighthouse Build Context
# ========================================
echo "Preparing lighthouse build context..."

# Copy testnet configuration
LIGHTHOUSE_TESTNET_BUILD="${LIGHTHOUSE_BUILD_DIR}/testnet"
mkdir -p "${LIGHTHOUSE_TESTNET_BUILD}"
cp -r "${LIGHTHOUSE_TESTNET_DIR}"/* "${LIGHTHOUSE_TESTNET_BUILD}/" 2>/dev/null || true

if [ ! -f "${LIGHTHOUSE_TESTNET_BUILD}/genesis.ssz" ] || [ ! -f "${LIGHTHOUSE_TESTNET_BUILD}/config.yaml" ]; then
    echo "⚠️  Warning: genesis.ssz or config.yaml missing from testnet directory" >&2
    echo "   Lighthouse may use mainnet configuration" >&2
fi

# Copy JWT secret
LIGHTHOUSE_JWT_DIR="${LIGHTHOUSE_BUILD_DIR}/ethereum"
mkdir -p "${LIGHTHOUSE_JWT_DIR}"
cp "${JWT_SECRET_SOURCE}" "${LIGHTHOUSE_JWT_DIR}/jwtsecret"
chmod 600 "${LIGHTHOUSE_JWT_DIR}/jwtsecret"

# Copy validator keys
LIGHTHOUSE_VALIDATORS_BUILD="${LIGHTHOUSE_BUILD_DIR}/validators"
mkdir -p "${LIGHTHOUSE_VALIDATORS_BUILD}"

if [ -d "${VALIDATOR_KEYS_DIR}" ] && [ "$(ls -A ${VALIDATOR_KEYS_DIR} 2>/dev/null)" ]; then
    echo "Copying validator keys..."
    cp -r "${VALIDATOR_KEYS_DIR}"/* "${LIGHTHOUSE_VALIDATORS_BUILD}/" 2>/dev/null || true

    # Always generate validator_definitions.yml if keys directory exists (ethereum-package format)
    # We regenerate even if the file exists to ensure it matches the current keys
    if [ -d "${LIGHTHOUSE_VALIDATORS_BUILD}/keys" ]; then
        echo "Generating validator_definitions.yml..."
        {
            echo "---"
            for keydir in "${LIGHTHOUSE_VALIDATORS_BUILD}/keys"/*; do
                if [ -d "${keydir}" ]; then
                    pubkey=$(basename "${keydir}")
                    keystore_path="/root/.lighthouse/validators/keys/${pubkey}/voting-keystore.json"
                    password_path="/root/.lighthouse/validators/secrets/${pubkey}"

                    # Only add if both keystore and password exist
                    if [ -f "${keydir}/voting-keystore.json" ] && [ -f "${LIGHTHOUSE_VALIDATORS_BUILD}/secrets/${pubkey}" ]; then
                        cat <<VALIDATOR_DEF
- enabled: true
  voting_public_key: "${pubkey}"
  type: local_keystore
  voting_keystore_path: ${keystore_path}
  voting_keystore_password_path: ${password_path}
VALIDATOR_DEF
                    fi
                fi
            done
        } > "${LIGHTHOUSE_VALIDATORS_BUILD}/validator_definitions.yml"

        num_validators=$(grep -c "enabled: true" "${LIGHTHOUSE_VALIDATORS_BUILD}/validator_definitions.yml" 2>/dev/null || echo "0")
        echo "✅ Generated validator_definitions.yml (${num_validators} validators)"
    else
        echo "⚠️  Warning: Keys directory not found after copy. Validator may not work."
    fi
else
    echo "⚠️  Warning: No validator keys found. Creating empty validators directory."
    touch "${LIGHTHOUSE_VALIDATORS_BUILD}/.gitkeep"
fi

echo "✅ Lighthouse build context ready"

# ========================================
# Process Dockerfile Templates
# ========================================
echo ""
echo "Processing Dockerfile templates..."

TEMPLATES_DIR="$(dirname "$0")/../templates"

# Process geth Dockerfile
GETH_TEMPLATE="${TEMPLATES_DIR}/geth.Dockerfile.template"
GETH_DOCKERFILE="${DOCKERFILES_DIR}/geth.Dockerfile"

if [ ! -f "${GETH_TEMPLATE}" ]; then
    echo "Error: Geth template not found: ${GETH_TEMPLATE}" >&2
    exit 1
fi

sed -e "s|{{GETH_BASE_IMAGE}}|${GETH_BASE_IMAGE}|g" \
    -e "s|{{CHAIN_ID}}|${CHAIN_ID}|g" \
    -e "s|{{LOG_FORMAT}}|${LOG_FORMAT}|g" \
    "${GETH_TEMPLATE}" > "${GETH_DOCKERFILE}"

echo "✅ Geth Dockerfile: ${GETH_DOCKERFILE}"

# Process lighthouse Dockerfile
LIGHTHOUSE_TEMPLATE="${TEMPLATES_DIR}/lighthouse.Dockerfile.template"
LIGHTHOUSE_DOCKERFILE="${DOCKERFILES_DIR}/lighthouse.Dockerfile"

if [ ! -f "${LIGHTHOUSE_TEMPLATE}" ]; then
    echo "Error: Lighthouse template not found: ${LIGHTHOUSE_TEMPLATE}" >&2
    exit 1
fi

# Convert log format for lighthouse (json -> JSON, terminal -> default)
LIGHTHOUSE_LOG_FORMAT="JSON"
if [ "${LOG_FORMAT}" = "terminal" ]; then
    LIGHTHOUSE_LOG_FORMAT="default"
fi

sed -e "s|{{LIGHTHOUSE_BASE_IMAGE}}|${LIGHTHOUSE_BASE_IMAGE}|g" \
    -e "s|{{GETH_SERVICE_NAME}}|${GETH_SERVICE_NAME}|g" \
    -e "s|{{LOG_FORMAT}}|${LIGHTHOUSE_LOG_FORMAT}|g" \
    "${LIGHTHOUSE_TEMPLATE}" > "${LIGHTHOUSE_DOCKERFILE}"

echo "✅ Lighthouse Dockerfile: ${LIGHTHOUSE_DOCKERFILE}"

# ========================================
# Build Docker Images
# ========================================
echo ""
echo "Building Docker images..."
echo ""

# Build geth image
echo "Building geth image: ${GETH_TAG}..."
if docker build -t "${GETH_TAG}" -f "${GETH_DOCKERFILE}" "${GETH_BUILD_DIR}"; then
    echo "✅ Geth image built successfully"
else
    echo "❌ Failed to build geth image" >&2
    exit 1
fi
echo ""

# Build lighthouse image
echo "Building lighthouse image: ${LIGHTHOUSE_TAG}..."
if docker build -t "${LIGHTHOUSE_TAG}" -f "${LIGHTHOUSE_DOCKERFILE}" "${LIGHTHOUSE_BUILD_DIR}"; then
    echo "✅ Lighthouse image built successfully"
else
    echo "❌ Failed to build lighthouse image" >&2
    exit 1
fi
echo ""

# ========================================
# Verify Images
# ========================================
echo "Verifying Docker images..."

if ! docker image inspect "${GETH_TAG}" >/dev/null 2>&1; then
    echo "❌ Geth image verification failed" >&2
    exit 1
fi
GETH_SIZE=$(docker image inspect "${GETH_TAG}" --format='{{.Size}}' | awk '{print int($1/1024/1024) "MB"}')
echo "  Geth image: ${GETH_TAG} (${GETH_SIZE})"

if ! docker image inspect "${LIGHTHOUSE_TAG}" >/dev/null 2>&1; then
    echo "❌ Lighthouse image verification failed" >&2
    exit 1
fi
LIGHTHOUSE_SIZE=$(docker image inspect "${LIGHTHOUSE_TAG}" --format='{{.Size}}' | awk '{print int($1/1024/1024) "MB"}')
echo "  Lighthouse image: ${LIGHTHOUSE_TAG} (${LIGHTHOUSE_SIZE})"

# ========================================
# Create Manifest
# ========================================
echo ""
echo "Creating image manifest..."

IMAGES_DIR="${OUTPUT_DIR}/l1-images"
mkdir -p "${IMAGES_DIR}"
MANIFEST_FILE="${IMAGES_DIR}/manifest.json"

cat > "${MANIFEST_FILE}" <<EOF
{
    "build_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "chain_id": "${CHAIN_ID}",
    "approach": "genesis-based",
    "geth": {
        "image_tag": "${GETH_TAG}",
        "base_image": "${GETH_BASE_IMAGE}",
        "size": "${GETH_SIZE}",
        "genesis_file": "${GENESIS_FILE}",
        "service_name": "${GETH_SERVICE_NAME}"
    },
    "lighthouse": {
        "image_tag": "${LIGHTHOUSE_TAG}",
        "base_image": "${LIGHTHOUSE_BASE_IMAGE}",
        "size": "${LIGHTHOUSE_SIZE}",
        "testnet_dir": "${LIGHTHOUSE_TESTNET_DIR}",
        "geth_service_name": "${GETH_SERVICE_NAME}"
    },
    "log_format": "${LOG_FORMAT}",
    "dockerfiles": {
        "geth": "${GETH_DOCKERFILE}",
        "lighthouse": "${LIGHTHOUSE_DOCKERFILE}"
    }
}
EOF

echo "✅ Image manifest created: ${MANIFEST_FILE}"

# ========================================
# Summary
# ========================================
echo ""
echo "=== Build Complete ==="
echo ""
echo "Images:"
echo "  Geth: ${GETH_TAG} (${GETH_SIZE})"
echo "  Lighthouse: ${LIGHTHOUSE_TAG} (${LIGHTHOUSE_SIZE})"
echo ""
echo "Manifest: ${MANIFEST_FILE}"
echo ""
echo "Next steps:"
echo "  1. Run: cd ${OUTPUT_DIR} && docker-compose up -d"
echo "  2. Wait ~30 seconds for services to start"
echo "  3. Verify blocks are increasing:"
echo "     docker exec l1-geth geth attach --exec 'eth.blockNumber' /root/.ethereum/geth.ipc"
echo ""
