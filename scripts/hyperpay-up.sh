#!/usr/bin/env bash
# S11b T5 — bring the HyperPay enclave up and print every address the later
# scripts need, resolved the T-j-safe way.
#
# Usage:
#   scripts/hyperpay-up.sh                 # clean, build/verify images, run
#   SKIP_BRINGUP=1 scripts/hyperpay-up.sh  # just re-resolve addresses
#   NO_BUILD=1 scripts/hyperpay-up.sh      # skip the hyperpay image build
#
# ORDERING (T1 finding, `mvp/results/s11b-environment.md` §6): `kurtosis clean
# -a` prunes UNUSED LOCAL IMAGES, and neither `hyperpay-node:local` nor
# `agglayer-contracts:hyperpay-local` has a registry to be re-pulled from. So
# the images are built/verified AFTER the clean, never before. `make e2e-images`
# is idempotent (~1s when both are present).
#
# T-j: `combined.json` is read with `jq` on the WHOLE object, per key, and any
# empty result is fatal. A `sed '/{/,/}/p'` range is selectively wrong here —
# the nested `pessimisticVKeyRouteALGateway` object closes the range at line 10
# of 42, so `polygonRollupManagerAddress` (line 2) survives and looks fine
# while `rollupAddress` — the AggchainPayments instance every assertion targets
# — resolves EMPTY.
#
# T-k: host-side reads use `curl` raw JSON-RPC. `cast`/`polycli` run INSIDE the
# enclave's toolbox container against in-network DNS.
set -euo pipefail

ENCLAVE="${ENCLAVE:-hyperpay}"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGS_FILE="${ARGS_FILE:-${PKG_DIR}/.github/tests/hyperpay/cdk-hyperpay.yml}"
HYPERPAY_REPO="${HYPERPAY_REPO:-/home/brolygon/repos/0xPolygon/hyperpay-wt/S11b-kurtosis-bridge-flow}"
OUT_ENV="${OUT_ENV:-${PKG_DIR}/.hyperpay-addresses.env}"

log() { printf '\n== %s\n' "$*"; }
die() { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }

if [ -z "${SKIP_BRINGUP:-}" ]; then
  log "kurtosis clean -a (removes enclaves AND prunes unused local images)"
  kurtosis clean -a

  if [ -z "${NO_BUILD:-}" ]; then
    log "building/verifying the two local images (AFTER the clean, see header)"
    make -C "${HYPERPAY_REPO}" e2e-images
  fi
  docker image inspect hyperpay-node:local >/dev/null \
    || die "hyperpay-node:local is gone; run \`make -C ${HYPERPAY_REPO} e2e-images\`"
  docker image inspect agglayer-contracts:hyperpay-local >/dev/null \
    || die "agglayer-contracts:hyperpay-local is gone; run \`make -C ${HYPERPAY_REPO} e2e-images\`"

  log "kurtosis run --enclave ${ENCLAVE}"
  # The engine sometimes fails a first `enclave create` on the logs-collector
  # health endpoint (T1 finding, §7). One retry after an engine restart, then
  # fatal — never a silent loop.
  if ! kurtosis run --enclave "${ENCLAVE}" --args-file "${ARGS_FILE}" "${PKG_DIR}"; then
    log "first kurtosis run failed; restarting the engine and retrying ONCE"
    kurtosis engine restart
    kurtosis clean -a
    make -C "${HYPERPAY_REPO}" e2e-images
    kurtosis run --enclave "${ENCLAVE}" --args-file "${ARGS_FILE}" "${PKG_DIR}" \
      || die "kurtosis run failed twice"
  fi
fi

log "enclave inspect"
kurtosis enclave inspect "${ENCLAVE}" || die "no enclave ${ENCLAVE}"

# --- combined.json, the T-j-safe way ---------------------------------------
CONTRACTS_SVC="$(kurtosis enclave inspect "${ENCLAVE}" 2>/dev/null \
  | grep -oE 'contracts-[0-9]+' | head -1)"
[ -n "${CONTRACTS_SVC}" ] || die "no contracts service in ${ENCLAVE}"

# Three things about this helper are the result of watching it fail:
#
#  * `jq -r --arg k <key> '.[$k]'` does NOT survive `kurtosis service exec`'s
#    quoting — the `$k` is eaten and every value comes back empty. A direct
#    `jq -rc .<key>` does.
#  * `kurtosis service exec` prints the COMMAND'S OUTPUT on stdout and its own
#    "The command was successfully executed" banner on stderr, then a trailing
#    blank line. So `| tail -1` returns the BLANK LINE, not the value — hence
#    `grep` for the value's shape rather than positional extraction.
#  * `rollupChainID` does not exist on this path (see the key-set note below).
jqkey() {
  local key="$1" val
  val="$(kurtosis service exec "${ENCLAVE}" "${CONTRACTS_SVC}" \
        "jq -rc .${key} /opt/zkevm/combined.json" 2>/dev/null \
        | tr -d '\r' | grep -E '^(0x[0-9a-fA-F]+|[0-9]+)$' | head -1)"
  if [ -z "${val}" ]; then
    printf '\n--- combined.json dump (key %s did not resolve) ---\n' "${key}" >&2
    kurtosis service exec "${ENCLAVE}" "${CONTRACTS_SVC}" \
      "cat /opt/zkevm/combined.json" >&2 || true
    die "combined.json key ${key} resolved EMPTY (trap T-j: never accept this silently)"
  fi
  printf '%s' "${val}"
}

log "resolving contract addresses from ${CONTRACTS_SVC}:/opt/zkevm/combined.json"
ROLLUP_MANAGER="$(jqkey polygonRollupManagerAddress)"
# THE key T-j silently loses. Every AggchainPayments assertion targets it.
ROLLUP_ADDRESS="$(jqkey rollupAddress)"
L1_BRIDGE="$(jqkey polygonZkEVMBridgeAddress)"
L1_GER="$(jqkey polygonZkEVMGlobalExitRootAddress)"
AGGLAYER_GATEWAY="$(jqkey aggLayerGatewayAddress)"
# THE KEY SET DIFFERS FROM T1's. `mvp/results/s11b-environment.md` §4 recorded
# 36 keys from the stock `ecdsa-multisig` preset. The payments/sovereign
# create-rollup path produces a DIFFERENT 34: no `rollupChainID`, no
# `rollupVerifierType`, no `forkID`, no `lastBatchSequenced`/`lastVerifiedBatch`
# family, no `aggOracleCommittee*`; and it adds `rollupID`,
# `consensusContract`, `consensusContractAddress`, `createRollupBlockNumber`,
# `defaultAggchainVKeyALGateway`, `programVKey`, `genesis`, `gasTokenAddress`,
# `firstBatchData`. Resolving a key by name from the wrong preset's list is a
# silent empty, which is exactly what T-j is about.
ROLLUP_ID="$(jqkey rollupID)"
# Proof the vkey registration actually landed: the gateway's stored default
# aggchain vkey for our selector, straight out of the deploy output.
DEFAULT_AGGCHAIN_VKEY="$(jqkey defaultAggchainVKeyALGateway.newAggchainVKey)"
DEFAULT_AGGCHAIN_SELECTOR="$(jqkey defaultAggchainVKeyALGateway.defaultAggchainSelector)"

# --- endpoints -------------------------------------------------------------
port() { kurtosis port print "${ENCLAVE}" "$1" "$2" 2>/dev/null | tr -d '\r'; }

L1_SVC="$(kurtosis enclave inspect "${ENCLAVE}" 2>/dev/null \
  | grep -oE 'el-1-[a-z]+-[a-z]+' | head -1)"
L1_RPC="$(port "${L1_SVC}" rpc || true)"
# `rpc` is the fork-wide port id, and the L2 RPC lives on the BRIDGE SHARD for
# this flavour (`L2_RPC_MAPPING[hyperpay]`), so generic consumers find it there.
L2_RPC="$(port hyperpay-bridge-shard-001 rpc || true)"
BRIDGE_REST_SVC="$(kurtosis enclave inspect "${ENCLAVE}" 2>/dev/null \
  | grep -oE 'aggkit-[0-9]+-bridge' | head -1)"
BRIDGE_REST="$(port "${BRIDGE_REST_SVC}" rest || true)"

# --- the HyperPay-owned values, from HyperPay ------------------------------
PROFILE="$(grep -E '^\s*hyperpay_stack_profile:' "${ARGS_FILE}" | awk '{print $2}')"
GENESIS_ROOT="$(docker run --rm hyperpay-node:local \
  hp-stack genesis-root --profile "${PROFILE}" 2>/dev/null | tr -d '\r')"
VKEY="$(docker run --rm hyperpay-node:local hp-stack vkey 2>/dev/null | tr -d '\r')"
FACADE_BRIDGE="$(docker run --rm hyperpay-node:local \
  hp-stack facades --profile "${PROFILE}" --field bridge 2>/dev/null | tr -d '\r')"
FACADE_GER="$(docker run --rm hyperpay-node:local \
  hp-stack facades --profile "${PROFILE}" --field ger-manager 2>/dev/null | tr -d '\r')"

cat > "${OUT_ENV}" <<EOF
# Generated by scripts/hyperpay-up.sh — source this in the check scripts.
ENCLAVE=${ENCLAVE}
CONTRACTS_SVC=${CONTRACTS_SVC}
L1_SVC=${L1_SVC}
L1_RPC=${L1_RPC}
L2_RPC=${L2_RPC}
BRIDGE_REST_SVC=${BRIDGE_REST_SVC}
BRIDGE_REST=${BRIDGE_REST}
ROLLUP_MANAGER=${ROLLUP_MANAGER}
ROLLUP_ADDRESS=${ROLLUP_ADDRESS}
L1_BRIDGE=${L1_BRIDGE}
L1_GER=${L1_GER}
AGGLAYER_GATEWAY=${AGGLAYER_GATEWAY}
ROLLUP_ID=${ROLLUP_ID}
DEFAULT_AGGCHAIN_VKEY=${DEFAULT_AGGCHAIN_VKEY}
DEFAULT_AGGCHAIN_SELECTOR=${DEFAULT_AGGCHAIN_SELECTOR}
HYPERPAY_PROFILE=${PROFILE}
HYPERPAY_GENESIS_ROOT=${GENESIS_ROOT}
HYPERPAY_VKEY=${VKEY}
HYPERPAY_FACADE_BRIDGE=${FACADE_BRIDGE}
HYPERPAY_FACADE_GER=${FACADE_GER}
EOF

log "resolved (also written to ${OUT_ENV})"
cat "${OUT_ENV}"
