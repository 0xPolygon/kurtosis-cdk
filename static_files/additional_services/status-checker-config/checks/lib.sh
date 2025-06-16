# shellcheck shell=bash
# This file defines common utility functions used by multiple bash-based status
# checks. It does NOT include a shebang so that the status-checker skips
# executing this file directly.

set -euo pipefail
set -o errtrace
trap 'echo "Error in ${BASH_SOURCE[0]} at line ${LINENO}." >&2' ERR

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

# check_batch checks if a batch is stuck.
check_batch() {
  local name="$1"             # e.g. "trusted", "verified", or "virtual"
  local rpc_method="$2"       # e.g. "zkevm_batchNumber" or "zkevm_verifiedBatchNumber"
  local threshold="${3:-12}"  # idle threshold (default: 12)

  local state_file="./$name.env"
  local error=0

  # shellcheck source=/dev/null
  [[ -f "$state_file" ]] && source "$state_file"

  local prev_batch_number="prev_${name}_batch_number"
  local prev_idle_counter="prev_${name}_batch_number_idle_counter"

  eval "${prev_batch_number}=\${${prev_batch_number}:-0}"
  eval "${prev_idle_counter}=\${${prev_idle_counter}:-0}"

  local batch_number
  batch_number="$(cast to-dec "$(cast rpc --rpc-url "$SEQUENCER_RPC_URL" "$rpc_method" | sed 's/\"//g')")"
  echo "${name^} Batch Number: $batch_number"

  if (( batch_number > ${!prev_batch_number} )); then
    eval "${prev_batch_number}=${batch_number}"
    eval "${prev_idle_counter}=0"
  else
    eval "${prev_idle_counter}=\$(( ${!prev_idle_counter} + 1 ))"
    if (( ${!prev_idle_counter} >= threshold )); then
      echo "ERROR: ${name^} batch number is stuck"
      error=1
    fi
  fi

  cat > "$state_file" <<EOF
${prev_batch_number}=${!prev_batch_number}
${prev_idle_counter}=${!prev_idle_counter}
EOF

  exit "$error"
}
