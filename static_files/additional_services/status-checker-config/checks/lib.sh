# shellcheck shell=bash
# This file defines common utility functions used by multiple bash-based status
# checks. It does NOT include a shebang so that the status-checker skips
# executing this file directly.

# is_consensus returns 0 if $CONSENSUS_CONTRACT_TYPE matches any argument, else 1.
is_consensus() {
  for consensus in "$@"; do
    if [[ "$CONSENSUS_CONTRACT_TYPE" == "$consensus" ]]; then
      return 0
    fi
  done
  return 1
}

# check_consensus checks if the consensus contract type isn't in the argument
# list, and will print a skip notice and exit 0 if true.
check_consensus() {
  if ! is_consensus "$@"; then
    echo "Skipping check, consensus must be one of: $*"
    exit 0
  fi
}
