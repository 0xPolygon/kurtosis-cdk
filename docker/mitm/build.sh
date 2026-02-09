#!/bin/bash
# Build custom mitmproxy image with eth-account support for transaction sender extraction

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${1:-kurtosis-mitm:with-eth-account}"

echo "Building custom mitmproxy image: $IMAGE_NAME"
cd "$SCRIPT_DIR"
docker build -t "$IMAGE_NAME" .

echo ""
echo "✓ Image built successfully: $IMAGE_NAME"
echo ""
echo "To use this image with Kurtosis CDK:"
echo "  1. Update src/package_io/constants.star:"
echo "     \"mitm_image\": \"$IMAGE_NAME\""
echo "  2. Run: kurtosis run --enclave my-enclave . '{\"deploy_mitm\": true, \"mitm_capture_transactions\": true}'"
echo ""
