#!/bin/bash
# Kurtosis version compatibility checker for snapshot tooling

set -euo pipefail

# Minimum required Kurtosis version for ethereum-package v6.0.0+
MIN_REQUIRED_VERSION="1.9.0"

# Get current Kurtosis version
CURRENT_VERSION=$(kurtosis version 2>/dev/null | grep "CLI Version" | awk '{print $3}' || echo "unknown")

# Function to compare versions
version_greater_equal() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# Function to print warning
print_warning() {
    echo "=================================================" >&2
    echo "WARNING: Kurtosis Version Compatibility Issue" >&2
    echo "=================================================" >&2
    echo "Current Kurtosis version: $CURRENT_VERSION" >&2
    echo "Minimum required version: $MIN_REQUIRED_VERSION" >&2
    echo "" >&2
    echo "The ethereum-package v6.0.0+ and optimism-package" >&2
    echo "require Kurtosis 1.9.0+ for the following features:" >&2
    echo "  - plan.get_cluster_type()" >&2
    echo "  - plan.get_tolerations()" >&2
    echo "" >&2
    echo "Solutions:" >&2
    echo "  1. Upgrade Kurtosis to 1.9.0 or later:" >&2
    echo "     - Homebrew: brew upgrade kurtosis-tech/tap/kurtosis-cli" >&2
    echo "     - APT: sudo apt update && sudo apt install kurtosis-cli" >&2
    echo "     - Manual: https://docs.kurtosis.com/upgrade/" >&2
    echo "" >&2
    echo "  2. Use older package versions (currently configured):" >&2
    echo "     - ethereum-package: 4.6.0 (downgraded from 6.0.0)" >&2
    echo "     - optimism-package: 2769472af (2025-10-18)" >&2
    echo "" >&2
    echo "Note: The downgraded versions may have compatibility" >&2
    echo "issues with newer Kurtosis features and Docker." >&2
    echo "=================================================" >&2
}

# Check version
if [ "$CURRENT_VERSION" = "unknown" ]; then
    echo "Error: Unable to determine Kurtosis version" >&2
    exit 1
fi

if ! version_greater_equal "$CURRENT_VERSION" "$MIN_REQUIRED_VERSION"; then
    print_warning

    # Check if we're in automated mode
    if [ "${KURTOSIS_VERSION_CHECK_STRICT:-false}" = "true" ]; then
        exit 1
    fi

    # Return warning code
    exit 2
fi

echo "Kurtosis version $CURRENT_VERSION is compatible" >&2
exit 0
