#!/bin/bash
set -e

# Check if the required arguments are provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <mode>"
  exit 1
fi

mode="$1"
requests=100
concurrency=1
rpc_url="{{.rpc_url}}"

echo "Running polycli loadtest (rpc_url=$rpc_url mode=$mode requests=$requests concurrency=$concurrency)..."
# shellcheck disable=SC1083,SC2086
polycli loadtest \
  --rpc-url "$rpc_url" \
  --chain-id {{.chain_id}} \
  --private-key "{{.private_key}}" \
  --verbosity 700 \
  --mode "$mode" \
  --requests "$requests" \
  --concurrency "$concurrency" \
  {{if .send_legacy_tx}}--legacy{{end}} \
  2>$1 | awk -v mode="$mode" -v url="$rpc_url" '{print "loadtest-" mode "-" url " " $0}'
