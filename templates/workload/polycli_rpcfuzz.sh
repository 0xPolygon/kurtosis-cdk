#!/bin/bash
set -e

echo "Running polycli rpcfuzz (rpc_url={{.rpc_url}})..."
polycli rpcfuzz \
  --rpc-url "{{.rpc_url}}" \
  --private-key "{{.private_key}}" \
  2>&1 | awk '{print "[rpcfuzz] " $0}'
