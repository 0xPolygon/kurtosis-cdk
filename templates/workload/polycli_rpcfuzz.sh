#!/bin/bash
set -e -x

cast send \
  --rpc-url "{{.rpc_url}}" \
  --private-key "{{.private_key}}" \
  --legacy \
  --json \
  --create "$(cat /opt/bindings/tokens/ERC20.bin)" > /opt/contract-deployment-receipt.json

polycli rpcfuzz \
  --rpc-url "{{.rpc_url}}" \
  --private-key "{{.private_key}}"
