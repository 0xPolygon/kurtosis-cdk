#!/bin/bash
# Build L1 Docker images from extracted state
#
# This script:
# 1. Reads L1 state manifest
# 2. Processes Dockerfile templates
# 3. Handles JWT secret generation
# 4. Builds geth and lighthouse Docker images
# 5. Creates image manifest

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="${SCRIPT_DIR}/../utils"

# Source utility functions
source "${UTILS_DIR}/logging.sh"
source "${UTILS_DIR}/prerequisites.sh"
source "${UTILS_DIR}/validation.sh"
source "${UTILS_DIR}/image-builder.sh"

# Exit codes
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_VALIDATION_ERROR=2
EXIT_CODE_PREREQ_ERROR=3

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

Build L1 Docker images from extracted state for snapshot.

Options:
    --output-dir DIR          Output directory containing extracted L1 state (required)
    --geth-image IMAGE         Geth base image (default: ethereum/client-go:v1.16.8)
    --lighthouse-image IMAGE  Lighthouse base image (default: sigp/lighthouse:v8.0.1)
    --geth-tag TAG             Tag for built geth image (default: l1-geth:snapshot)
    --lighthouse-tag TAG       Tag for built lighthouse image (default: l1-lighthouse:snapshot)
    --geth-service-name NAME   Docker-compose service name for geth (default: l1-geth)
    --log-format FORMAT        Log format: json or terminal (default: json)
    -h, --help                 Show this help message

Example:
    $0 \\
        --output-dir ./snapshot-output \\
        --geth-tag my-geth:snapshot \\
        --lighthouse-tag my-lighthouse:snapshot
EOF
    exit 1
}

# Parse arguments
parse_args() {
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
    
    # Validate output directory exists
    if [ ! -d "${OUTPUT_DIR}" ]; then
        echo "Error: Output directory does not exist: ${OUTPUT_DIR}" >&2
        exit 1
    fi
}

# Read L1 state manifest
read_l1_manifest() {
    local manifest_file="${OUTPUT_DIR}/l1-state/manifest.json"

    if [ ! -f "${manifest_file}" ]; then
        echo "Error: L1 state manifest not found: ${manifest_file}" >&2
        echo "Hint: Run extract-l1-state.sh first" >&2
        exit 1
    fi

    # Extract values using jq
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed" >&2
        exit 1
    fi

    GENESIS_FILE="${OUTPUT_DIR}/l1-state/genesis.json"
    LIGHTHOUSE_TESTNET_DIR="${OUTPUT_DIR}/l1-state/lighthouse-testnet"
    VALIDATOR_KEYS_DIR="${OUTPUT_DIR}/l1-state/validator-keys"
    CHAIN_ID=$(jq --raw-output '.chain_id // 271828' "${manifest_file}" 2>/dev/null || echo "271828")

    # Validate genesis file exists
    if [ ! -f "${GENESIS_FILE}" ]; then
        echo "Error: Genesis file not found: ${GENESIS_FILE}" >&2
        exit 1
    fi

    # Lighthouse testnet dir is required
    if [ ! -d "${LIGHTHOUSE_TESTNET_DIR}" ]; then
        echo "Error: Lighthouse testnet config not found: ${LIGHTHOUSE_TESTNET_DIR}" >&2
        exit 1
    fi

    # Set up build context directories for genesis-based approach
    # These directories will contain the files needed for the Docker build
    GETH_DATADIR="${OUTPUT_DIR}/l1-state/geth"
    LIGHTHOUSE_DATADIR="${OUTPUT_DIR}/l1-state/lighthouse"
    mkdir -p "${GETH_DATADIR}" "${LIGHTHOUSE_DATADIR}"

    # Copy genesis file to geth build context
    cp "${GENESIS_FILE}" "${GETH_DATADIR}/"

    echo "L1 Manifest loaded:"
    echo "  Chain ID: ${CHAIN_ID}"
    echo "  Genesis file: ${GENESIS_FILE}"
    echo "  Lighthouse testnet: ${LIGHTHOUSE_TESTNET_DIR}"
    echo "  Validator keys: ${VALIDATOR_KEYS_DIR}"
    echo ""
}

# Process Dockerfile templates
process_templates() {
    local dockerfiles_dir="${OUTPUT_DIR}/dockerfiles"
    mkdir -p "${dockerfiles_dir}"
    
    local templates_dir="${SCRIPT_DIR}/../templates"
    
    echo "Processing Dockerfile templates..."
    
    # Process geth Dockerfile
    local geth_template="${templates_dir}/geth.Dockerfile.template"
    local geth_dockerfile="${dockerfiles_dir}/geth.Dockerfile"
    
    if [ ! -f "${geth_template}" ]; then
        echo "Error: Geth template not found: ${geth_template}" >&2
        exit 1
    fi
    
    replace_template_vars "${geth_template}" "${geth_dockerfile}" \
        "GETH_BASE_IMAGE=${GETH_BASE_IMAGE}" \
        "CHAIN_ID=${CHAIN_ID}" \
        "LOG_FORMAT=${LOG_FORMAT}"
    
    echo "✅ Geth Dockerfile generated: ${geth_dockerfile}"
    
    # Process lighthouse Dockerfile
    local lighthouse_template="${templates_dir}/lighthouse.Dockerfile.template"
    local lighthouse_dockerfile="${dockerfiles_dir}/lighthouse.Dockerfile"
    
    if [ ! -f "${lighthouse_template}" ]; then
        echo "Error: Lighthouse template not found: ${lighthouse_template}" >&2
        exit 1
    fi
    
    # Convert log format for lighthouse (JSON -> JSON, terminal -> default)
    local lighthouse_log_format="JSON"
    if [ "${LOG_FORMAT}" = "terminal" ]; then
        lighthouse_log_format="default"
    fi
    
    replace_template_vars "${lighthouse_template}" "${lighthouse_dockerfile}" \
        "LIGHTHOUSE_BASE_IMAGE=${LIGHTHOUSE_BASE_IMAGE}" \
        "GETH_SERVICE_NAME=${GETH_SERVICE_NAME}" \
        "LOG_FORMAT=${lighthouse_log_format}"
    
    echo "✅ Lighthouse Dockerfile generated: ${lighthouse_dockerfile}"
    echo ""
}

# Handle JWT secret and testnet config
handle_jwt_secret() {
    echo "Handling JWT secret and testnet configuration..."

    # Ensure JWT secret exists in geth datadir
    ensure_jwt_secret "${GETH_DATADIR}"

    # Copy JWT secret to lighthouse datadir so it's baked into the lighthouse image
    # This allows lighthouse to access the JWT without volume mounts
    echo "Copying JWT secret to lighthouse datadir..."
    local jwt_source="${GETH_DATADIR}/jwtsecret"
    local jwt_dest_dir="${LIGHTHOUSE_DATADIR}/ethereum"
    local jwt_dest="${jwt_dest_dir}/jwtsecret"

    if [ ! -f "${jwt_source}" ]; then
        echo "Error: JWT secret not found at ${jwt_source}" >&2
        exit 1
    fi

    mkdir -p "${jwt_dest_dir}"
    cp "${jwt_source}" "${jwt_dest}"
    chmod 600 "${jwt_dest}"
    echo "✅ JWT secret copied to lighthouse datadir"

    # Copy testnet configuration to lighthouse datadir for Docker build
    # The Dockerfile expects the testnet directory to be in the build context
    local testnet_source="${OUTPUT_DIR}/l1-state/lighthouse-testnet"
    local testnet_dest="${LIGHTHOUSE_DATADIR}/testnet"

    if [ -d "${testnet_source}" ] && [ "$(ls -A ${testnet_source} 2>/dev/null)" ]; then
        echo "Copying testnet configuration to lighthouse build context..."
        mkdir -p "${testnet_dest}"
        cp -r "${testnet_source}"/* "${testnet_dest}/" 2>/dev/null || true
        echo "✅ Testnet configuration copied to lighthouse datadir"

        # Verify critical files
        if [ -f "${testnet_dest}/genesis.ssz" ] && [ -f "${testnet_dest}/config.yaml" ]; then
            echo "✅ Verified genesis.ssz and config.yaml are present"
        else
            echo "⚠️  Warning: genesis.ssz or config.yaml missing from testnet directory"
            echo "   Lighthouse may use mainnet configuration"
        fi
    else
        echo "⚠️  Warning: Testnet configuration directory not found or empty"
        echo "   Location: ${testnet_source}"
        echo "   Lighthouse will use mainnet configuration (this will cause issues)"
        echo "   This may happen if snapshot was created with an older version"
    fi

    # Copy validator keys to lighthouse datadir for Docker build
    # The validator service needs these keys to propose blocks
    # Always create the validators directory (even if empty) so Docker COPY doesn't fail
    local validator_keys_source="${OUTPUT_DIR}/l1-state/validator-keys"
    local validator_keys_dest="${LIGHTHOUSE_DATADIR}/validators"

    mkdir -p "${validator_keys_dest}"

    if [ -d "${validator_keys_source}" ] && [ "$(ls -A ${validator_keys_source} 2>/dev/null)" ]; then
        echo "Copying validator keys to lighthouse build context..."
        cp -r "${validator_keys_source}"/* "${validator_keys_dest}/" 2>/dev/null || true
        echo "✅ Validator keys copied to lighthouse datadir"

        # Generate validator_definitions.yml if it doesn't exist (ethereum-package format)
        if [ ! -f "${validator_keys_dest}/validator_definitions.yml" ] && [ -d "${validator_keys_dest}/keys" ]; then
            echo "Generating validator_definitions.yml from ethereum-package keystores..."
            {
                echo "---"
                for keydir in "${validator_keys_dest}/keys"/*; do
                    if [ -d "${keydir}" ]; then
                        local pubkey=$(basename "${keydir}")
                        local keystore_path="/root/.lighthouse/validators/keys/${pubkey}/voting-keystore.json"
                        local password_path="/root/.lighthouse/validators/secrets/${pubkey}"

                        # Only add if both keystore and password exist
                        if [ -f "${keydir}/voting-keystore.json" ] && [ -f "${validator_keys_dest}/secrets/${pubkey}" ]; then
                            cat <<EOF
- enabled: true
  voting_public_key: "${pubkey}"
  type: local_keystore
  voting_keystore_path: ${keystore_path}
  voting_keystore_password_path: ${password_path}
EOF
                        fi
                    fi
                done
            } > "${validator_keys_dest}/validator_definitions.yml"
            echo "✅ Generated validator_definitions.yml"
        fi

        # Verify critical files
        if [ -f "${validator_keys_dest}/validator_definitions.yml" ]; then
            echo "✅ Verified validator_definitions.yml is present"
            local num_validators=$(grep -c "enabled: true" "${validator_keys_dest}/validator_definitions.yml" 2>/dev/null || echo "0")
            echo "   Number of validators: ${num_validators}"
        else
            echo "⚠️  Warning: validator_definitions.yml missing"
            echo "   Validator service will not be able to propose blocks"
        fi

        # Note: Slashing protection database will be initialized by lighthouse at first run
        # using the --init-slashing-protection flag in docker-compose
    else
        echo "⚠️  Warning: Validator keys directory not found or empty"
        echo "   Location: ${validator_keys_source}"
        echo "   Creating empty validators directory for Docker build"
        echo "   Validator service will not be able to propose blocks"
        echo "   L1 will remain at current block height"
        # Create empty .gitkeep to ensure directory is not empty for COPY
        touch "${validator_keys_dest}/.gitkeep"
    fi
    echo ""
}

# Build Docker images
build_images() {
    echo "Building Docker images..."
    echo ""
    
    # Build geth image
    echo "Building geth image: ${GETH_TAG}..."
    if docker build -t "${GETH_TAG}" -f "${OUTPUT_DIR}/dockerfiles/geth.Dockerfile" "${GETH_DATADIR}"; then
        echo "✅ Geth image built successfully"
    else
        echo "❌ Failed to build geth image" >&2
        exit 1
    fi
    echo ""
    
    # Build lighthouse image
    echo "Building lighthouse image: ${LIGHTHOUSE_TAG}..."
    if docker build -t "${LIGHTHOUSE_TAG}" -f "${OUTPUT_DIR}/dockerfiles/lighthouse.Dockerfile" "${LIGHTHOUSE_DATADIR}"; then
        echo "✅ Lighthouse image built successfully"
    else
        echo "❌ Failed to build lighthouse image" >&2
        exit 1
    fi
    echo ""
}

# Verify images
verify_images() {
    echo "Verifying Docker images..."
    
    if validate_docker_image "${GETH_TAG}"; then
        local geth_size=$(get_image_size "${GETH_TAG}")
        echo "  Geth image size: ${geth_size}"
    else
        echo "❌ Geth image verification failed" >&2
        exit 1
    fi
    
    if validate_docker_image "${LIGHTHOUSE_TAG}"; then
        local lighthouse_size=$(get_image_size "${LIGHTHOUSE_TAG}")
        echo "  Lighthouse image size: ${lighthouse_size}"
    else
        echo "❌ Lighthouse image verification failed" >&2
        exit 1
    fi
    
    echo ""
}

# Create image manifest
create_image_manifest() {
    local images_dir="${OUTPUT_DIR}/l1-images"
    mkdir -p "${images_dir}"
    
    local manifest_file="${images_dir}/manifest.json"
    
    local geth_size=$(get_image_size "${GETH_TAG}")
    local lighthouse_size=$(get_image_size "${LIGHTHOUSE_TAG}")
    
    cat > "${manifest_file}" <<EOF
{
    "build_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "chain_id": "${CHAIN_ID}",
    "geth": {
        "image_tag": "${GETH_TAG}",
        "base_image": "${GETH_BASE_IMAGE}",
        "size": "${geth_size}",
        "datadir_path": "${GETH_DATADIR}",
        "service_name": "${GETH_SERVICE_NAME}"
    },
    "lighthouse": {
        "image_tag": "${LIGHTHOUSE_TAG}",
        "base_image": "${LIGHTHOUSE_BASE_IMAGE}",
        "size": "${lighthouse_size}",
        "datadir_path": "${LIGHTHOUSE_DATADIR}",
        "geth_service_name": "${GETH_SERVICE_NAME}"
    },
    "log_format": "${LOG_FORMAT}",
    "dockerfiles": {
        "geth": "${OUTPUT_DIR}/dockerfiles/geth.Dockerfile",
        "lighthouse": "${OUTPUT_DIR}/dockerfiles/lighthouse.Dockerfile"
    }
}
EOF
    
    echo "✅ Image manifest created: ${manifest_file}"
    echo ""
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ ${exit_code} -ne 0 ]; then
        log_error "Script failed with exit code ${exit_code}"
        if [ -n "${LOG_FILE}" ]; then
            log_error "Check log file for details: ${LOG_FILE}"
        fi
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main function
main() {
    log_step "1" "L1 Docker Image Build"
    
    # Parse arguments
    parse_args "$@"
    
    # Setup logging
    setup_logging "${OUTPUT_DIR}" || {
        echo "Error: Failed to setup logging" >&2
        exit ${EXIT_CODE_GENERAL_ERROR}
    }
    
    # Check prerequisites
    log_section "Checking prerequisites"
    if ! check_docker; then
        log_error "Prerequisites check failed"
        exit ${EXIT_CODE_PREREQ_ERROR}
    fi
    
    if ! check_output_dir "${OUTPUT_DIR}"; then
        log_error "Output directory check failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    log_success "Prerequisites check passed"
    
    # Read L1 manifest
    log_section "Reading L1 manifest"
    read_l1_manifest
    
    # Validate L1 state
    if ! validate_l1_state "${OUTPUT_DIR}/l1-state"; then
        log_error "L1 state validation failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    log_success "L1 state validated"
    
    # Process templates
    process_templates
    
    # Handle JWT secret
    handle_jwt_secret
    
    # Build images
    build_images
    
    # Verify images
    log_section "Verifying Docker images"
    verify_images
    
    # Additional validation
    if ! validate_docker_image "${GETH_TAG}"; then
        log_error "Geth image validation failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    if ! validate_docker_image "${LIGHTHOUSE_TAG}"; then
        log_error "Lighthouse image validation failed"
        exit ${EXIT_CODE_VALIDATION_ERROR}
    fi
    
    log_success "All Docker images validated"
    
    # Create manifest
    create_image_manifest
    
    log_section "Summary"
    log_info "Images:"
    log_info "  Geth: ${GETH_TAG}"
    log_info "  Lighthouse: ${LIGHTHOUSE_TAG}"
    log_info "Manifest: ${OUTPUT_DIR}/l1-images/manifest.json"
    
    log_success "L1 Docker Image Build Complete"
}

# Run main function
main "$@"
