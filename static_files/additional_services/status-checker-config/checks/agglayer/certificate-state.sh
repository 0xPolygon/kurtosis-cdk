#!/usr/bin/env bash

# shellcheck source=static_files/additional_services/status-checker-config/checks/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"

check_consensus pessimistic fep

prev_cert="./certificate-state.json"
l2_bridge_address=$(jq -r '.polygonZkEVML2BridgeAddress' /opt/zkevm/combined.json)
network_id=$(cast call --rpc-url "$L2_RPC_URL" "$l2_bridge_address" 'networkID()(uint32)')

curr_json=$(cast rpc --rpc-url "$AGGLAYER_RPC_URL" interop_getLatestKnownCertificateHeader "$network_id")

curr_id=$(echo "$curr_json" | jq -r '.certificate_id')
curr_status=$(echo "$curr_json" | jq -r '.status')

write_certificate() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$curr_json" | jq --arg timestamp "$timestamp" '. + {timestamp: $timestamp}' > "$prev_cert"
}

if [[ ! -f "$prev_cert" ]]; then
  write_certificate
  exit 0
fi

prev_id=$(jq -r '.certificate_id' "$prev_cert")
prev_status=$(jq -r '.status' "$prev_cert")

if [[ "$curr_id" != "$prev_id" || "$curr_status" != "$prev_status" ]]; then
  write_certificate
  exit 0
fi

prev_timestamp=$(jq -r '.timestamp' "$prev_cert")
prev_epoch=$(date -d "$prev_timestamp" +%s)
now_epoch=$(date -u +%s)
diff=$((now_epoch - prev_epoch))

if (( diff > 120 )) && [[ "$prev_status" != "Settled" ]]; then
  echo "ERROR: Certificate is stuck with ${prev_status,,} status diff=$diff"
  exit 1
fi

if (( diff > 300 )); then
  echo "WARN: Certificate is stuck with ${prev_status,,} status diff=$diff"
fi
