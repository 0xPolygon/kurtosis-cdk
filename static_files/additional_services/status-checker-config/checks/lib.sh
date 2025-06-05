# shellcheck shell=bash
# This file defines common utility functions used by multiple bash-based status
# checks. It does NOT include a shebang so that the status-checker framework
# skips executing this file directly.

check_consensus() {
  for consensus in "$@"; do
    if [[ "$CONSENSUS_CONTRACT_TYPE" == "$consensus" ]]; then
      return 0
    fi
  done
  echo "Skipping check, consensus must be one of: $*"
  return 1
}
