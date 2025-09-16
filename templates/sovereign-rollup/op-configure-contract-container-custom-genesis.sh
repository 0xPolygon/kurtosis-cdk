#!/bin/sh

# --- strict-ish mode ---
set -eu
# pipefail is not POSIX, emulate by careful checking
trap 'echo "[`date -Is`] ERROR on line $LINENO (exit $?)" >&2; exit 1' ERR INT HUP TERM

# --- resolve script directory & log file ---
# $0 may be relative, so normalise
SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
  /*) : ;;                           # absolute
  *) SCRIPT_PATH="$(pwd)/$SCRIPT_PATH" ;;
esac
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
LOG_FILE="$SCRIPT_DIR/$(basename "$0").log"

# redirect everything to console AND log
# (this works fine in /bin/sh without process substitution)
exec > >(tee -a "$LOG_FILE") 2>&1
# if process substitution isn't available, fall back to plain redirection:
# exec >"$LOG_FILE" 2>&1

log() { echo "[`date -Is`] $*"; }

log "=== START $(basename "$0") ==="
log "Logging to: $LOG_FILE"

# 0) Preconditions
for bin in jq cast npx; do
  command -v "$bin" >/dev/null 2>&1 || { log "Missing required tool: $bin"; exit 1; }
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

# 4) Run createGenesis
log "Running 1_createGenesis.ts"
oldpwd="$(pwd)"
cd /opt/zkevm-contracts || exit 1
MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete" \
  npx ts-node deployment/v2/1_createGenesis.ts
cd "$oldpwd"

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
global_exit_root_address="$(jq -r '.polygonZkEVMGlobalExitRootAddress' /opt/zkevm/combined.json)"
case "$global_exit_root_address" in
  0x[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*)
    : ;;
  *) log "Invalid address: $global_exit_root_address"; exit 1 ;;
esac

# 8) Initialize contract
log "Sending initialize() to $global_exit_root_address"
cast send "$global_exit_root_address" "initialize()" \
  --private-key "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625" \
  --rpc-url "http://el-1-geth-lighthouse:8545"

log "SUCCESS: script completed with no errors."
