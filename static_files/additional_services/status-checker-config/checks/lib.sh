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
  local rpc_method="$2"       # e.g. "zkevm_batchNumber", "zkevm_verifiedBatchNumber", or "zkevm_virtualBatchNumber"
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

check_certificate_height() {
  local name="$1"       # e.g. "known", "pending", or "settled"
  local rpc_method="$2" # e.g. "interop_getLatestKnownCertificateHeader", "interop_getLatestPendingCertificateHeader", or "interop_getLatestSettledCertificateHeader"

  local l2_bridge_address network_id
  l2_bridge_address=$(jq -r '.polygonZkEVML2BridgeAddress' /opt/zkevm/combined.json)
  network_id=$(cast call --rpc-url "$L2_RPC_URL" "$l2_bridge_address" 'networkID()(uint32)')

  local prev_header="./prev-$name-certificate-header.json"
  local curr_header="./curr-$name-certificate-header.json"

  cast rpc --rpc-url "$AGGLAYER_RPC_URL" "$rpc_method" "$network_id" | jq '.' > "$curr_header"

  # Skip the check if there hasn't been a certificate at any point.
  if jq -e '. == null' "$curr_header" > /dev/null; then
     return 0
  fi

  # Copy the current to previous on function exit if not null.
  trap '[[ -f "$curr_header" ]] && cp "$curr_header" "$prev_header"' RETURN

  # Skip the check if there is no previous certificate.
  if [[ ! -f "$prev_header" ]]; then
    return 0
  fi

  # Skip the check if there hasn't been a new certificate.
  local prev_id curr_id
  prev_id=$(jq -r '.certificate_id' "$prev_header")
  curr_id=$(jq -r '.certificate_id' "$curr_header")
  if [[ "$prev_id" == "$curr_id" ]]; then
     return 0
  fi

  # Certificate height must increase.
  local prev_height curr_height
  prev_height=$(jq -r '.height' "$prev_header")
  curr_height=$(jq -r '.height' "$curr_header")
  if (( curr_height <= prev_height )); then
    echo "ERROR: ${name^} certificate height not increasing: prev=$prev_height, curr=$curr_height"
    return 1
  fi

  # Certificate epoch_number must increase for settled certificates.
  if [[ "$name" == "settled" ]]; then
    local prev_epoch curr_epoch
    prev_epoch=$(jq -r '.epoch_number' "$prev_header")
    curr_epoch=$(jq -r '.epoch_number' "$curr_header")

    if (( curr_epoch <= prev_epoch )); then
      echo "ERROR: ${name^} certificate epoch_number not increasing: prev=$prev_epoch, curr=$curr_epoch"
      return 1
    fi
  fi

  trap - RETURN # unset
  return 0
}
