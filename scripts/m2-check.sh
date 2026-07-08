#!/usr/bin/env bash
#
# m2-check.sh — Agglayer Payments v2, M2 gate: from a clean machine, bring up
# the full cdk-payments kurtosis stack and assert that a (mock) certificate
# SETTLES on L1 (AggchainPayments rollup exit root updated via the pessimistic-
# proof verification path).
#
# Reproducible from clean:
#   scripts/m2-check.sh            # builds images, kurtosis clean -a, run, assert
#   NO_BUILD=1 scripts/m2-check.sh # skip image builds (reuse local images)
#
# Exit 0 iff a certificate reaches Settled and the L1 rollup exit root is
# non-zero within $SETTLE_TIMEOUT seconds; non-zero (with diagnostics) otherwise.
#
# Env knobs:
#   ENCLAVE          kurtosis enclave name              (default: cdk-payments)
#   ARGS_FILE        preset args file                    (default: .github/tests/payments/cdk-payments.yml)
#   PAYCHAIN_DIR     paychain checkout (for the binary)  (default: ~/repos/agglayer/paychain)
#   CONTRACTS_DIR    agglayer-contracts payments worktree(default: ~/repos/worktrees/agglayer-contracts--payments)
#   SETTLE_TIMEOUT   seconds to wait for settlement      (default: 1800)
#   NO_BUILD         if set, skip docker/binary builds
set -uo pipefail

KURTOSIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENCLAVE="${ENCLAVE:-cdk-payments}"
ARGS_FILE="${ARGS_FILE:-.github/tests/payments/cdk-payments.yml}"
PAYCHAIN_DIR="${PAYCHAIN_DIR:-$HOME/repos/agglayer/paychain}"
CONTRACTS_DIR="${CONTRACTS_DIR:-$HOME/repos/worktrees/agglayer-contracts--payments}"
SETTLE_TIMEOUT="${SETTLE_TIMEOUT:-1800}"

log()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 1. Build images (paychain-node:local + agglayer-contracts:payments-local).
# ---------------------------------------------------------------------------
if [[ -z "${NO_BUILD:-}" ]]; then
  log "Building paychain-node release binary + image"
  ( cd "$PAYCHAIN_DIR" \
      && PATH="$HOME/.sp1/bin:$HOME/.cargo/bin:$PATH" cargo build --release -p paychain-node \
      && docker build -t paychain-node:local . ) \
    || { fail "paychain-node image build"; exit 1; }

  if ! docker image inspect agglayer-contracts:payments-local >/dev/null 2>&1; then
    log "Building agglayer-contracts:payments-local tooling image"
    ( cd "$CONTRACTS_DIR" \
        && docker build -t agglayer-contracts:payments-local -f Dockerfile.kurtosis . ) \
      || { fail "contracts image build"; exit 1; }
  fi
fi

# ---------------------------------------------------------------------------
# 2. Clean + run the full stack.
# ---------------------------------------------------------------------------
log "kurtosis clean -a"
kurtosis clean -a >/dev/null 2>&1

log "kurtosis run --enclave $ENCLAVE"
if ! kurtosis run --enclave "$ENCLAVE" --args-file "$ARGS_FILE" "$KURTOSIS_DIR"; then
  fail "kurtosis run did not complete"
  kurtosis enclave inspect "$ENCLAVE" || true
  exit 1
fi

AGGKIT_SVC="aggkit-001"
CONTRACTS_SVC="contracts-001"

# ---------------------------------------------------------------------------
# 3. Resolve L1 RPC + RollupManager address for the on-chain assertion.
# ---------------------------------------------------------------------------
log "Resolving L1 RPC + rollup manager"
L1_RPC="$(kurtosis port print "$ENCLAVE" el-1-geth-lighthouse rpc 2>/dev/null \
       || kurtosis port print "$ENCLAVE" el-1-geth-teku rpc 2>/dev/null \
       || true)"
# combined.json is a flat JSON object printed verbatim by `kurtosis service exec`
# (no wrapper/prefix). Do NOT range-filter with sed '/{/,/}/p': the file has
# nested objects (e.g. pessimisticVKeyRouteALGateway {...}) and the first nested
# '}' would truncate the stream *before* the manager address, yielding empty.
# Read the whole object and grep the specific key. Prefer the canonical
# polygonRollupManagerAddress; fall back to the AgglayerManager alias.
addr_field() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"0x[0-9a-fA-F]{40}\"" | grep -oE '0x[0-9a-fA-F]{40}' | head -1; }
COMBINED="$(kurtosis service exec "$ENCLAVE" "$CONTRACTS_SVC" 'cat /opt/zkevm/combined.json' 2>/dev/null)"
ROLLUP_MGR="$(echo "$COMBINED" | addr_field 'polygonRollupManagerAddress')"
[[ -z "$ROLLUP_MGR" ]] && ROLLUP_MGR="$(echo "$COMBINED" | addr_field 'AgglayerManager')"
if [[ -z "$ROLLUP_MGR" ]]; then
  fail "could not resolve ROLLUP_MGR from ${CONTRACTS_SVC}:/opt/zkevm/combined.json"
  echo "$COMBINED" | head -40
fi
echo "L1_RPC=$L1_RPC  ROLLUP_MGR=$ROLLUP_MGR"

# cast helper: prefer host cast, else the foundry container.
cast_call() {
  if command -v cast >/dev/null 2>&1; then cast "$@";
  else docker run --rm --network host ghcr.io/foundry-rs/foundry:latest cast "$@"; fi
}

rollup_exit_root() {
  # RollupManager.getRollupExitRoot() -> bytes32
  [[ -n "$L1_RPC" && -n "$ROLLUP_MGR" ]] || return 1
  cast_call call "$ROLLUP_MGR" 'getRollupExitRoot()(bytes32)' --rpc-url "$L1_RPC" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 4. Poll for settlement: aggsender log marker AND (best-effort) a non-zero
#    L1 rollup exit root.
# ---------------------------------------------------------------------------
log "Waiting up to ${SETTLE_TIMEOUT}s for a settled certificate"
ZERO="0x0000000000000000000000000000000000000000000000000000000000000000"
# Capture the pre-settlement rollup exit root as a baseline: on a freshly
# created AggchainPayments rollup this is already NON-ZERO, so "settled" means
# the value CHANGED from this baseline (the pessimistic-proof verification path
# updated it), not merely "non-zero".
BASELINE_RER="$(rollup_exit_root || true)"
echo "BASELINE rollup exit root = ${BASELINE_RER:-<unavailable>}"
deadline=$(( $(date +%s) + SETTLE_TIMEOUT ))
settled_log=""
rer=""
while (( $(date +%s) < deadline )); do
  logs="$(kurtosis service logs "$ENCLAVE" "$AGGKIT_SVC" 2>/dev/null)"
  settled_log="$(echo "$logs" | grep -iE 'certificate.*settled|status.*Settled|new settled certificate' | tail -3)"
  rer="$(rollup_exit_root || true)"
  rer_changed=""
  [[ -n "$rer" && "$rer" != "$ZERO" && "$rer" != "$BASELINE_RER" ]] && rer_changed="yes"
  if [[ -n "$settled_log" && -n "$rer_changed" ]] || [[ -n "$rer_changed" ]]; then
    log "SETTLED"
    echo "--- aggsender settlement log ---"; echo "$settled_log"
    echo "--- L1 rollup exit root: baseline -> current ---"; echo "${BASELINE_RER} -> ${rer}"
    echo "--- last settle tx in agglayer logs ---"
    kurtosis service logs "$ENCLAVE" agglayer 2>/dev/null | grep -iE 'settl|verifyPessimistic|onVerifyPessimistic' | tail -5
    exit 0
  fi
  sleep 15
done

fail "no settled certificate within ${SETTLE_TIMEOUT}s"
echo "--- aggsender tail ---"; kurtosis service logs "$ENCLAVE" "$AGGKIT_SVC" 2>/dev/null | tail -40
echo "--- agglayer tail ---";  kurtosis service logs "$ENCLAVE" agglayer 2>/dev/null | tail -40
echo "--- paychain-node tail ---"; kurtosis service logs "$ENCLAVE" paychain-node-001 2>/dev/null | tail -40
exit 1
