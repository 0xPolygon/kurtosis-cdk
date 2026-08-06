#!/usr/bin/env bash
# S11b T5 — assert the four things that can each kill the step, in order:
# the contract deploy, the vkey + genesis-root seeding, the aggoracle
# handshake, and aggkit's ability to see the bridge shard as a chain.
#
# Run `scripts/hyperpay-up.sh` first; this reads its `.hyperpay-addresses.env`.
#
# T-k: every host-side chain read here is a `curl` raw `eth_call`. T-l:
# settlement is NEVER detected via `getRollupExitRoot()` — it is non-zero from
# the first second (measured in `mvp/results/s11b-environment.md` §6) — so this
# script records a BASELINE and the settlement assertions compare against it.
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PKG_DIR}/.hyperpay-addresses.env}"
[ -f "${ENV_FILE}" ] || { echo "no ${ENV_FILE}; run scripts/hyperpay-up.sh first"; exit 1; }
# shellcheck disable=SC1090
. "${ENV_FILE}"
BASELINE="${BASELINE:-${PKG_DIR}/.hyperpay-baseline.env}"

PASS=0
FAIL=0
ok()   { printf '  PASS  %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
note() { printf '  note  %s\n' "$*"; }
sect() { printf '\n== %s\n' "$*"; }

# Raw eth_call over curl. `$1` to-address, `$2` calldata; echoes the 0x result.
ethcall() {
  curl -s -X POST -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$1\",\"data\":\"$2\"},\"latest\"]}" \
    "http://${L1_RPC}" | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p'
}
# Same, against the bridge shard's own JSON-RPC (already a full URL).
l2call() {
  curl -s -X POST -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$1\",\"data\":\"$2\"},\"latest\"]}" \
    "${L2_RPC}" | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p'
}

sect "1. AggchainPayments deployed, and seeded the way trap T-a demands"
# Selectors verified in the precedent and reusable verbatim (plan §2).
LAST_STATE_ROOT="$(ethcall "${ROLLUP_ADDRESS}" 0xb70de0d9)"   # lastStateRoot()
LATEST_BLOCK="$(ethcall "${ROLLUP_ADDRESS}" 0x4599c788)"      # latestBlockNumber()
note "lastStateRoot()     = ${LAST_STATE_ROOT}"
note "latestBlockNumber() = ${LATEST_BLOCK}"
note "hp-stack genesis-root = ${HYPERPAY_GENESIS_ROOT}"
if [ "${LAST_STATE_ROOT}" = "${HYPERPAY_GENESIS_ROOT}" ]; then
  ok "lastStateRoot() == hp-stack genesis-root (trap T-a caught at bring-up)"
else
  bad "lastStateRoot() ${LAST_STATE_ROOT} != genesis-root ${HYPERPAY_GENESIS_ROOT} -- agglayer would reject EVERY certificate with 'Aggchain hash mismatch'"
fi
# `startingBlockNumber: 0` (trap T-b).
if [ "$(( ${LATEST_BLOCK:-1} ))" -eq 0 ] 2>/dev/null; then
  ok "latestBlockNumber() == 0 == startingBlockNumber (trap T-b's starting point)"
else
  bad "latestBlockNumber() is ${LATEST_BLOCK}, expected 0"
fi

sect "2. The owned aggchain vkey, registered under 0x10000001"
note "deploy output selector = ${DEFAULT_AGGCHAIN_SELECTOR}"
note "deploy output vkey     = ${DEFAULT_AGGCHAIN_VKEY}"
note "hp-stack vkey          = ${HYPERPAY_VKEY}"
[ "${DEFAULT_AGGCHAIN_SELECTOR}" = "0x10000001" ] \
  && ok "selector is AGGCHAIN_VKEY_SELECTOR 0x10000001" \
  || bad "selector is ${DEFAULT_AGGCHAIN_SELECTOR}, expected 0x10000001"
[ "${DEFAULT_AGGCHAIN_VKEY}" = "${HYPERPAY_VKEY}" ] \
  && ok "registered vkey == hp-stack vkey (the aggregator's own wire value)" \
  || bad "registered ${DEFAULT_AGGCHAIN_VKEY} != hp-stack ${HYPERPAY_VKEY}"
# And it must be non-zero, or `addDefaultAggchainVKey` could not have accepted
# it: `bytes32(0)` is AgglayerGateway's "absent" sentinel and the call reverts
# VKeyCannotBeZero() (0x6745305e). This is the assertion the first bring-up
# taught us to make.
case "${DEFAULT_AGGCHAIN_VKEY}" in
  0x0000000000000000000000000000000000000000000000000000000000000000)
    bad "the registered vkey is the empty word; AgglayerGateway reverts VKeyCannotBeZero() on it" ;;
  *) ok "the registered vkey is non-zero (VKeyCannotBeZero() cannot have fired)" ;;
esac

sect "3. Services: everything running, nothing restarting"
INSPECT="$(kurtosis enclave inspect "${ENCLAVE}" 2>/dev/null)"
TOTAL="$(printf '%s' "${INSPECT}" | grep -cE '(RUNNING|STOPPED)')"
NOTRUNNING="$(printf '%s' "${INSPECT}" | grep -E 'STOPPED' || true)"
HP_RUNNING="$(printf '%s' "${INSPECT}" | grep -E 'hyperpay-' | grep -c RUNNING)"
note "services with a status: ${TOTAL}; HyperPay services RUNNING: ${HP_RUNNING}"
[ -z "${NOTRUNNING}" ] && ok "no STOPPED service" || bad "STOPPED: ${NOTRUNNING}"
# 14 HyperPay services: bridge shard, 2x(DA+sequencer+replica+shard-prover),
# 2 gateways, aggregator, NATS, Redis.
[ "${HP_RUNNING}" -eq 14 ] \
  && ok "all 14 HyperPay services RUNNING" \
  || bad "expected 14 HyperPay services RUNNING, found ${HP_RUNNING}"
for svc in $(printf '%s' "${INSPECT}" | grep -oE '[a-z0-9-]+-00[0-9]' | sort -u); do
  restarts="$(docker inspect --format '{{.RestartCount}}' \
    "$(docker ps -a --filter "name=${svc}" --format '{{.ID}}' | head -1)" 2>/dev/null || echo 0)"
  [ "${restarts:-0}" -eq 0 ] || bad "${svc} has restarted ${restarts} time(s)"
done
ok "restart counts checked"

sect "4. agglayer: no BalanceUnderflow / InError (trap T-d/T-l hard fail)"
AGG_LOGS="$(kurtosis service logs "${ENCLAVE}" agglayer 2>/dev/null | tail -400)"
if printf '%s' "${AGG_LOGS}" | grep -qE 'BalanceUnderflow|InError'; then
  bad "agglayer logged BalanceUnderflow/InError"
  printf '%s\n' "${AGG_LOGS}" | grep -E 'BalanceUnderflow|InError' | head -5
else
  ok "no BalanceUnderflow / InError in agglayer's last 400 log lines"
fi

sect "5a. trap T-n: the bridge shard answers globalExitRootUpdater() with the aggoracle EOA"
# Selector 0x7c314ce3 == globalExitRootUpdater(). (0x9e56f4d8 was a guess and
# returned no result at all -- a reminder that a wrong selector reads as
# "feature missing", which is why every selector here is `cast sig`-derived.)
GER_UPDATER_CALL="$(l2call "${HYPERPAY_FACADE_GER}" 0x7c314ce3)"
EXPECTED_UPDATER="$(kurtosis service exec "${ENCLAVE}" hyperpay-bridge-shard-001 \
  "printenv HYPERPAY_BRIDGE_GER_UPDATER_ADDRESS" 2>/dev/null | tr -d '\r' \
  | grep -oE '0x[0-9a-fA-F]{40}' | head -1)"
note "globalExitRootUpdater()                = ${GER_UPDATER_CALL:-<no result>}"
note "HYPERPAY_BRIDGE_GER_UPDATER_ADDRESS    = ${EXPECTED_UPDATER:-<unset>}"
if [ -n "${GER_UPDATER_CALL}" ] && [ -n "${EXPECTED_UPDATER}" ] \
   && [ "$(printf '%s' "${GER_UPDATER_CALL}" | tail -c 40 | tr 'A-Z' 'a-z')" \
      = "$(printf '%s' "${EXPECTED_UPDATER#0x}" | tr 'A-Z' 'a-z')" ]; then
  ok "trap T-n satisfied: the GER facade names the aggkit aggoracle EOA, so aggoracle will start"
else
  bad "trap T-n: globalExitRootUpdater() ${GER_UPDATER_CALL} != aggoracle EOA ${EXPECTED_UPDATER} -- aggoracle refuses to run"
fi

sect "5b. aggoracle actually injecting: is a GER visible on the bridge shard?"
AGGKIT_LOGS="$(kurtosis service logs "${ENCLAVE}" aggkit-001 2>/dev/null | tail -400)"
if printf '%s' "${AGGKIT_LOGS}" | grep -qiE 'aggoracle'; then
  note "aggoracle is running (log lines present); last error line, if any:"
  printf '%s\n' "${AGGKIT_LOGS}" | grep -iE 'ERROR.*aggoracle|aggoracle.*ERROR' \
    | tail -2 | sed 's/^/        /'
else
  bad "no aggoracle lines at all in aggkit-001's last 400 log lines"
fi
printf '%s' "${AGGKIT_LOGS}" | grep -qiE '\bpanic\b|\bFATAL\b' \
  && bad "aggkit-001 panicked / logged FATAL" \
  || ok "aggkit-001 has no panic and no FATAL"

L1_LAST_GER="$(ethcall "${L1_GER}" 0x3ed691ef)"   # getLastGlobalExitRoot()
L2_BLOCK="$(curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
  "${L2_RPC}" | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p')"
GER_MAPPED="$(l2call "${HYPERPAY_FACADE_GER}" "0x257b3632${L1_LAST_GER#0x}")"  # globalExitRootMap(bytes32)
note "L1 getLastGlobalExitRoot()  = ${L1_LAST_GER}"
note "bridge shard eth_blockNumber = ${L2_BLOCK}"
note "bridge shard globalExitRootMap(<that GER>) = ${GER_MAPPED}"
case "${GER_MAPPED}" in
  ""|0x0000000000000000000000000000000000000000000000000000000000000000)
    bad "no GER has landed on the bridge shard"
    if [ "${L2_BLOCK}" = "0x0" ]; then
      cat <<'DIAG'
        DIAGNOSIS -- one root cause, already recorded:
        The bridge shard is at block 0x0 and stays there.
        `hyperpay-bridge-shard/src/main.rs` runs NO block-production loop (its
        own step-1a comment says so). aggoracle's insertGlobalExitRoot tx is
        accepted by the JSON-RPC overlay and then NEVER MINED, so aggkit's
        ethtxmanager reports `failed to add tx to get monitored: already
        exists` on every 10s retry and the GER never reaches state.
        The SAME missing loop blocks the settlement fold (the aggregator's
        mandatory bridge child has no SBP). One wiring task unblocks both.
        See mvp/results/QUESTIONS.md, "S11b (T6) — the local settlement fold
        is blocked".
DIAG
    fi
    ;;
  *) ok "a GER has landed on the bridge shard (globalExitRootMap non-zero)" ;;
esac

sect "6. aggkit bridgesync sees the bridge shard as a chain"
for nid in 0 1; do
  code="$(curl -s -o /dev/null -w '%{http_code}' \
    "${BRIDGE_REST}/bridge/v1/bridges?network_id=${nid}")"
  [ "${code}" = "200" ] \
    && ok "bridge REST /bridge/v1/bridges?network_id=${nid} -> 200" \
    || bad "bridge REST /bridge/v1/bridges?network_id=${nid} -> ${code}"
done

sect "7. T-l baseline (NEVER a settlement signal, only a comparison point)"
RER="$(ethcall "${ROLLUP_MANAGER}" 0xa2967d99)"   # getRollupExitRoot()
PSU_COUNT="$(curl -s -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"fromBlock\":\"0x0\",\"toBlock\":\"latest\",\"address\":\"${ROLLUP_ADDRESS}\",\"topics\":[\"0xb093baec53b3de33590cc9c750af0710b04a205c4400ebc158bdd5ca847724ec\"]}]}" \
  "http://${L1_RPC}" | grep -o '"transactionHash"' | wc -l)"
cat > "${BASELINE}" <<EOF
# T-l baseline, recorded at bring-up. getRollupExitRoot() is NON-ZERO from the
# first second (measured, mvp/results/s11b-environment.md §6), so it is a false
# positive as a settlement detector; the settlement assertions compare
# PaymentsStateUpdated counts and latestBlockNumber() against these values.
BASE_ROLLUP_EXIT_ROOT=${RER}
BASE_PAYMENTS_STATE_UPDATED_COUNT=${PSU_COUNT}
BASE_LATEST_BLOCK_NUMBER=${LATEST_BLOCK}
EOF
note "getRollupExitRoot()           = ${RER}"
note "PaymentsStateUpdated log count = ${PSU_COUNT}"
note "baseline written to ${BASELINE}"
[ "${PSU_COUNT}" -eq 0 ] \
  && ok "no PaymentsStateUpdated yet, as expected before any settlement" \
  || note "PaymentsStateUpdated already ${PSU_COUNT} -- treat as the baseline"

printf '\n=== %d passed, %d failed ===\n' "${PASS}" "${FAIL}"
[ "${FAIL}" -eq 0 ]
