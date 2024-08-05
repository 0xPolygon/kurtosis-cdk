#!/bin/bash

# This script will set up the Kurtosis CDK environment.
#
# Show usage:
# $ ./setup.sh --help
#
# Install the tools using the default versions:
# $ ./setup.sh
#
# Install the tools with specific versions:
# $ ./setup.sh --kurtosis-version 1.0.0 --yq-version v4.44.3 --foundry-version nightly

set -e

# Define default tool versions.
KURTOSIS_VERSION="1.0.0"  # https://github.com/kurtosis-tech/kurtosis/releases
YQ_VERSION="v4.44.3"      # https://github.com/mikefarah/yq/releases
FOUNDRY_VERSION="nightly" # https://github.com/foundry-rs/foundry/releases

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --kurtosis-version  Specify kurtosis version (default: $KURTOSIS_VERSION)"
  echo "  --yq-version        Specify yq version (default: $YQ_VERSION)"
  echo "  --foundry-version   Specify foundry version (default: $FOUNDRY_VERSION)"
  echo "  -h, --help          Display this help message"
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --kurtosis-version)
      KURTOSIS_VERSION="$2"
      shift 2
      ;;
    --yq-version)
      YQ_VERSION="$2"
      shift 2
      ;;
    --foundry-version)
      FOUNDRY_VERSION="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    esac
  done
}

install_kurtosis() {
  local kurtosis_version=$1
  echo "deb [trusted=yes] https://apt.fury.io/kurtosis-tech/ /" | sudo tee /etc/apt/sources.list.d/kurtosis.list
  sudo apt update
  sudo apt install --yes kurtosis-cli="$kurtosis_version"
  kurtosis analytics disable
}

install_yq() {
  local yq_version=$1
  sudo curl -L "https://github.com/mikefarah/yq/releases/download/$yq_version/yq_linux_amd64" --output /usr/bin/yq
  sudo chmod +x /usr/bin/yq
}

install_foundry() {
  local foundry_version=$1
  curl -L https://foundry.paradigm.xyz | bash
  export PATH="$PATH:/home/runner/.config/.foundry/bin"
  foundryup --version "$foundry_version"
}

main() {
  # Parse command line arguments
  parse_arguments "$@"

  # Install tools.
  echo "> Installing dependencies"
  sudo apt install --yes curl git

  echo -e "\n> Installing kurtosis version $KURTOSIS_VERSION"
  install_kurtosis "$KURTOSIS_VERSION"

  echo -e "\n> Installing yq version $YQ_VERSION"
  install_yq "$YQ_VERSION"

  echo -e "\n> Installing foundry version $FOUNDRY_VERSION"
  install_foundry "$FOUNDRY_VERSION"

  echo -e "\n> Setup complete"

  # Show tool versions.
  echo -e "\n$ forge --version"
  forge --version

  echo -e "\n$ yq --version"
  yq --version

  echo -e "\n$ kurtosis version"
  kurtosis version
}

# Call main function with all script arguments
main "$@"
