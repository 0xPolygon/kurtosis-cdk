#!/usr/bin/env bash

# shellcheck source=static_files/additional_services/status-checker/checks/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"

check_consensus pessimistic fep

prev_cert="./certificate-status.json"
l2_bridge_address=$(jq -r '.polygonZkEVML2BridgeAddress' /opt/output/combined.json)
network_id=$(cast call --rpc-url "$L2_RPC_URL" "$l2_bridge_address" 'networkID()(uint32)')

curr_json=$(cast rpc --rpc-url "$AGGLAYER_RPC_URL" interop_getLatestKnownCertificateHeader "$network_id")

# Skip the check if there hasn't been a certificate at any point.
if echo "$curr_json" | jq -e '. == null' > /dev/null; then
  exit 0
fi

curr_id=$(echo "$curr_json" | jq -r '.certificate_id')
curr_status=$(echo "$curr_json" | jq -r '.status')

write_certificate() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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
  echo "ERROR: Certificate is stuck status=${prev_status,,} diff=${diff}s"
  exit 1
fi

if (( diff > 300 )); then
  echo "WARN: Certificate is stuck status=${prev_status,,} diff=${diff}s"
fi
