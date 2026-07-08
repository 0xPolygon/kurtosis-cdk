#!/usr/bin/env bash
#
# m2-check.sh — Agglayer Payments v2, M2 gate: from a clean machine, bring up
# the full cdk-payments kurtosis stack and assert that (mock) certificates
# SETTLE on L1 via the pessimistic-proof verification path.
#
# Settlement detection (D1b-fix3): assert directly against the per-rollup
# AggchainPayments contract on L1, NOT via RollupManager.getRollupExitRoot().
# In the payments flow, native funds enter via bridge claims and the demo runs
# transfer-only load, so certificates settle DURING bring-up (before any
# baseline could be captured) and the rollup exit root does not necessarily
# change on every settlement. The authoritative, per-settlement signal is
# AggchainPayments.onVerifyPessimistic, which on each verified certificate:
#   - sets  lastStateRoot   = newStateRoot
#   - sets  latestBlockNumber = endBlock
#   - emits PaymentsStateUpdated(bytes32 indexed newStateRoot,
#                                uint256 indexed endBlock)
# So we poll eth_getLogs for PaymentsStateUpdated and eth_call
# lastStateRoot()/latestBlockNumber(), and require MULTIPLE settlements with a
# strictly-advancing latestBlockNumber (proves sustained, no-underflow
# settlement — a stuck InError cert would stop advancing it).
#
# Reproducible from clean:
#   scripts/m2-check.sh            # builds images, kurtosis clean -a, run, assert
#   NO_BUILD=1 scripts/m2-check.sh # skip image builds (reuse local images)
#
# Exit 0 iff at least $REQUIRE_SETTLEMENTS PaymentsStateUpdated events are
# observed with a strictly-advancing latestBlockNumber within $SETTLE_TIMEOUT
# seconds; non-zero (with diagnostics) otherwise.
#
# Env knobs:
#   ENCLAVE             kurtosis enclave name              (default: cdk-payments)
#   ARGS_FILE           preset args file                    (default: .github/tests/payments/cdk-payments.yml)
#   PAYCHAIN_DIR        paychain checkout (for the binary)  (default: ~/repos/agglayer/paychain)
#   CONTRACTS_DIR       agglayer-contracts payments worktree(default: ~/repos/worktrees/agglayer-contracts--payments)
#   SETTLE_TIMEOUT      seconds to wait for settlement      (default: 1800)
#   REQUIRE_SETTLEMENTS min PaymentsStateUpdated events     (default: 3)
#   NO_BUILD            if set, skip docker/binary builds
#   SKIP_BRINGUP        if set, assert against an already-running enclave
set -uo pipefail

KURTOSIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENCLAVE="${ENCLAVE:-cdk-payments}"
ARGS_FILE="${ARGS_FILE:-.github/tests/payments/cdk-payments.yml}"
PAYCHAIN_DIR="${PAYCHAIN_DIR:-$HOME/repos/agglayer/paychain}"
CONTRACTS_DIR="${CONTRACTS_DIR:-$HOME/repos/worktrees/agglayer-contracts--payments}"
SETTLE_TIMEOUT="${SETTLE_TIMEOUT:-1800}"
REQUIRE_SETTLEMENTS="${REQUIRE_SETTLEMENTS:-3}"

log()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; }

# SKIP_BRINGUP=1 asserts against an already-running enclave (no build/clean/run)
# — used to re-validate settlement detection without a full rebuild.
if [[ -n "${SKIP_BRINGUP:-}" ]]; then
  log "SKIP_BRINGUP set — asserting against already-running enclave $ENCLAVE"
else

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

fi  # end SKIP_BRINGUP guard

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
# The per-rollup AggchainPayments contract (the settlement target we assert
# against). combined.json records it as `rollupAddress`; fall back to the
# consensus alias if the layout ever changes.
AGGCHAIN_PAYMENTS="$(echo "$COMBINED" | addr_field 'rollupAddress')"
[[ -z "$AGGCHAIN_PAYMENTS" ]] && AGGCHAIN_PAYMENTS="$(echo "$COMBINED" | addr_field 'consensusContractAddress')"
if [[ -z "$AGGCHAIN_PAYMENTS" ]]; then
  fail "could not resolve AggchainPayments (rollupAddress) from ${CONTRACTS_SVC}:/opt/zkevm/combined.json"
  echo "$COMBINED" | head -40
fi
echo "L1_RPC=$L1_RPC  ROLLUP_MGR=$ROLLUP_MGR  AGGCHAIN_PAYMENTS=$AGGCHAIN_PAYMENTS"

# RPC reader via curl (raw eth_call). We deliberately avoid `cast` here: the
# `kurtosis port print ... rpc` mapping is a schemeless host:port, and some cast
# builds fail to connect to that loopback docker-proxy port ("Connection
# refused") while curl connects fine; curl is also always present. Normalize the
# endpoint to a full http:// URL.
L1_URL="$L1_RPC"; [[ -n "$L1_URL" && "$L1_URL" != http* ]] && L1_URL="http://$L1_URL"

# eth_call <to> <4byte-selector-or-calldata> -> 0x-prefixed return data (or empty)
eth_call() {
  local to="$1" data="$2"
  [[ -n "$L1_URL" && -n "$to" ]] || return 1
  curl -s -m 10 "$L1_URL" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$to\",\"data\":\"$data\"},\"latest\"],\"id\":1}" \
    2>/dev/null | grep -oE '"result":"0x[0-9a-fA-F]*"' | grep -oE '0x[0-9a-fA-F]+' | head -1
}

# AggchainPayments.latestBlockNumber() -> uint256. Selector 0x4599c788.
latest_block_number() { eth_call "$AGGCHAIN_PAYMENTS" '0x4599c788'; }
# AggchainPayments.lastStateRoot() -> bytes32. Selector 0xb70de0d9.
last_state_root() { eth_call "$AGGCHAIN_PAYMENTS" '0xb70de0d9'; }

# Count of PaymentsStateUpdated(bytes32 indexed newStateRoot,
# uint256 indexed endBlock) logs emitted by the AggchainPayments contract.
# topic0 = keccak256("PaymentsStateUpdated(bytes32,uint256)").
PSU_TOPIC='0xb093baec53b3de33590cc9c750af0710b04a205c4400ebc158bdd5ca847724ec'
psu_logs() {
  [[ -n "$L1_URL" && -n "$AGGCHAIN_PAYMENTS" ]] || return 1
  curl -s -m 15 "$L1_URL" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"$AGGCHAIN_PAYMENTS\",\"fromBlock\":\"0x0\",\"toBlock\":\"latest\",\"topics\":[\"$PSU_TOPIC\"]}],\"id\":1}" 2>/dev/null
}
# Count occurrences robustly: grep exits 1 on no-match which, under
# `set -o pipefail`, would fail the whole pipeline — capture in a var and
# normalise to digits so the count is always a clean integer ("0" when none).
psu_count() {
  local n
  n="$(psu_logs | grep -oE "\"topics\":\[\"$PSU_TOPIC\"" | wc -l)"
  n="${n//[^0-9]/}"; echo "${n:-0}"
}
# Hex (0x-prefixed, possibly 64-char zero-padded) -> decimal. Strip the 0x and
# leading zeros so bash arithmetic never sees a >16-digit literal.
hex2dec() {
  local h="${1#0x}"
  h="${h#"${h%%[!0]*}"}"                       # strip leading zeros
  [[ -z "$h" ]] && { echo 0; return; }
  [[ "$h" == *[!0-9a-fA-F]* ]] && { echo 0; return; }
  echo $(( 16#$h ))
}

# ---------------------------------------------------------------------------
# 4. Poll for SUSTAINED settlement on the AggchainPayments contract.
#    Require >= REQUIRE_SETTLEMENTS PaymentsStateUpdated events AND a
#    strictly-advancing latestBlockNumber (a stuck InError certificate would
#    freeze both — which is exactly the D1b-fix3 BalanceUnderflow symptom).
# ---------------------------------------------------------------------------
log "Waiting up to ${SETTLE_TIMEOUT}s for >= ${REQUIRE_SETTLEMENTS} settlements (PaymentsStateUpdated) with advancing latestBlockNumber"
first_lbn="$(hex2dec "$(latest_block_number)")"
echo "initial latestBlockNumber = ${first_lbn}"
deadline=$(( $(date +%s) + SETTLE_TIMEOUT ))
count=0; lbn="$first_lbn"; advanced=""
while (( $(date +%s) < deadline )); do
  count="$(psu_count)"
  lbn="$(hex2dec "$(latest_block_number)")"
  (( lbn > first_lbn )) && advanced="yes"
  echo "  [$(date +%T)] PaymentsStateUpdated=${count} latestBlockNumber=${lbn}"
  if (( count >= REQUIRE_SETTLEMENTS )) && [[ -n "$advanced" ]]; then
    log "SETTLED (sustained)"
    echo "--- AggchainPayments = ${AGGCHAIN_PAYMENTS} ---"
    echo "PaymentsStateUpdated events: ${count} (>= ${REQUIRE_SETTLEMENTS})"
    echo "latestBlockNumber: ${first_lbn} -> ${lbn} (advanced)"
    echo "lastStateRoot: $(last_state_root)"
    echo "--- PaymentsStateUpdated (newStateRoot, endBlock) ---"
    psu_logs | grep -oE '"topics":\["'"$PSU_TOPIC"'","0x[0-9a-f]+","0x[0-9a-f]+"\]' \
      | sed -E 's/.*,"(0x[0-9a-f]+)","(0x[0-9a-f]+)"\]/  newStateRoot=\1 endBlock=\2/' || true
    echo "--- last settle tx in agglayer logs ---"
    kurtosis service logs "$ENCLAVE" agglayer 2>/dev/null | grep -iE 'settl|verifyPessimistic|onVerifyPessimistic' | tail -5
    # Guard: no certificate should be stuck InError (BalanceUnderflow etc.).
    if kurtosis service logs "$ENCLAVE" agglayer 2>/dev/null | grep -qiE 'BalanceUnderflow'; then
      fail "a certificate hit BalanceUnderflow — PP value-conservation invariant violated"
      kurtosis service logs "$ENCLAVE" agglayer 2>/dev/null | grep -iE 'BalanceUnderflow|InError' | tail -5
      exit 1
    fi
    exit 0
  fi
  sleep 15
done

fail "did not observe ${REQUIRE_SETTLEMENTS} sustained settlements within ${SETTLE_TIMEOUT}s (last: count=${count}, latestBlockNumber=${lbn})"
echo "--- aggsender tail ---"; kurtosis service logs "$ENCLAVE" "$AGGKIT_SVC" 2>/dev/null | tail -40
echo "--- agglayer tail ---";  kurtosis service logs "$ENCLAVE" agglayer 2>/dev/null | tail -40
echo "--- paychain-node tail ---"; kurtosis service logs "$ENCLAVE" paychain-node-001 2>/dev/null | tail -40
exit 1
