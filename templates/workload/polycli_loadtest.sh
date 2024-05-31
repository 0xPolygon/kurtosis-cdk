#!/bin/bash
set -e -x

# Check if the required arguments are provided
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <mode>"
  exit 1
fi

mode="$1"
requests=100
concurrency=1
rpc_url="{{.rpc_url}}"

# shellcheck disable=SC1083,SC2086
polycli loadtest \
  --rpc-url "$rpc_url" \
  --private-key "{{.private_key}}" \
  --verbosity 700 \
  --mode "$mode" \
  --requests "$requests" \
  --concurrency "$concurrency" \
  --legacy
