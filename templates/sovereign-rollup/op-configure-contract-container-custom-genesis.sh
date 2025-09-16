{% comment %} #!/bin/bash

cp /opt/contract-deploy/op-custom-genesis-addresses.json /opt/zkevm/combined.json

sed -i 's#http://127.0.0.1:8545#{{.l1_rpc_url}}#' /opt/zkevm-contracts/hardhat.config.ts
cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json

pushd /opt/zkevm-contracts || exit 1
MNEMONIC="{{.l1_preallocated_mnemonic}}" npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
popd || exit 1

cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm/
cp /opt/zkevm/combined.json /opt/zkevm/combined-001.json

global_exit_root_address=$(jq -r '.polygonZkEVMGlobalExitRootAddress' /opt/zkevm/combined.json)
cast send "$global_exit_root_address" "initialize()" --private-key "{{.zkevm_l2_admin_private_key}}" --rpc-url "{{.l1_rpc_url}}" {% endcomment %}


#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR on line $LINENO"; exit 1' ERR

log() { echo "[$(date -Is)] $*"; }

# 0) Preconditions
for bin in jq cast npx; do
  command -v "$bin" >/dev/null || { echo "Missing required tool: $bin"; exit 1; }
done

# 1) Copy combined addresses
log "Copying op-custom-genesis-addresses.json -> /opt/zkevm/combined.json"
cp /opt/contract-deploy/op-custom-genesis-addresses.json /opt/zkevm/combined.json
test -s /opt/zkevm/combined.json

# 2) Point Hardhat at the EL endpoint
log "Rewriting RPC URL in hardhat.config.ts"
sed -i 's#http://127.0.0.1:8545#http://el-1-geth-lighthouse:8545#' /opt/zkevm-contracts/hardhat.config.ts
grep -q 'http://el-1-geth-lighthouse:8545' /opt/zkevm-contracts/hardhat.config.ts

# 3) Copy deploy parameters
log "Copying deploy_parameters.json"
cp /opt/contract-deploy/deploy_parameters.json /opt/zkevm-contracts/deployment/v2/deploy_parameters.json
test -s /opt/zkevm-contracts/deployment/v2/deploy_parameters.json

# 4) Run createGenesis and capture logs (pipefail will propagate failures)
log "Running 1_createGenesis.ts"
pushd /opt/zkevm-contracts >/dev/null
MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" \
  npx ts-node deployment/v2/1_createGenesis.ts 2>&1 | tee 02_create_genesis.out
popd >/dev/null

# 5) Verify genesis.json produced
test -s /opt/zkevm-contracts/deployment/v2/genesis.json

# 6) Copy artifacts
log "Copying artifacts to /opt/zkevm"
cp /opt/zkevm-contracts/deployment/v2/genesis.json /opt/zkevm/
cp /opt/contract-deploy/create_rollup_parameters.json /opt/zkevm/
cp /opt/zkevm/combined.json /opt/zkevm/combined-001.json
test -s /opt/zkevm/genesis.json
test -s /opt/zkevm/create_rollup_parameters.json
test -s /opt/zkevm/combined-001.json

# 7) Extract address and sanity-check it
global_exit_root_address=$(jq -r '.polygonZkEVMGlobalExitRootAddress' /opt/zkevm/combined.json)
[[ "$global_exit_root_address" =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "Invalid address: $global_exit_root_address"; exit 1; }

# 8) Initialize contract
log "Sending initialize() to $global_exit_root_address"
cast send "$global_exit_root_address" "initialize()" \
  --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
  --rpc-url "http://el-1-geth-lighthouse:8545"

log "SUCCESS: script completed with no errors."
