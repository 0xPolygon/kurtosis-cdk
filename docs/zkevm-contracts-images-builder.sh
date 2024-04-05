#!/bin/bash
set -e

# The repository of the image.
# The image will be called $repository/zkevm-contracts.
repository="$1"

build_and_push_zkevm_contracts_image() {
  fork="$1"
  branch="$2"

  echo "Building and pushing $repository/zkevm-contracts:$fork..."
  docker buildx build . \
    --tag "$repository/zkevm-contracts:$fork" \
    --build-arg "ZKEVM_CONTRACTS_BRANCH=$branch" \
    --build-arg "POLYCLI_VERSION=v0.1.42" \
    --file ./docs/zkevm-contracts.Dockerfile \
    --platform linux/amd64,linux/arm64 \
    --builder container \
    --push
}

build_and_push_zkevm_contracts_image "fork4" "v1.1.0-fork.4"
build_and_push_zkevm_contracts_image "fork5" "v2.0.0-fork.5"
build_and_push_zkevm_contracts_image "fork6" "v3.0.0-fork.6"
build_and_push_zkevm_contracts_image "fork7" "v4.0.0-fork.7"
build_and_push_zkevm_contracts_image "fork8" "v5.0.1-rc.2-fork.8"
build_and_push_zkevm_contracts_image "fork9" "develop"
