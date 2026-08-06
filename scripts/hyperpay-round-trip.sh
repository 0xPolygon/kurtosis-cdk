#!/usr/bin/env bash
# S11b — the full round trip: L1 -> HyperPay -> payments -> HyperPay -> L1.
#
#   L1 deposit -> claim on the bridge shard          (T7, composed below)
#   -> paced payments across both shards             (hp-scenario, stock)
#   -> withdrawal as a payment-shard bridge_exit_intent
#   -> LET leaf + BridgeEvent + aggkit bridgesync
#   -> settlement: onVerifyPessimistic writes lastStateRoot on L1
#   -> claimAsset on L1, exact delta to a non-payer recipient
#
# Usage (needs a running enclave from scripts/hyperpay-up.sh):
#   scripts/hyperpay-round-trip.sh
#   WITHDRAW_WEI=200000000000000000 REQUIRE_SETTLEMENTS=3 scripts/hyperpay-round-trip.sh
#   SKIP_DEPOSIT=1 scripts/hyperpay-round-trip.sh    # reuse an existing claim
#
# ---------------------------------------------------------------------------
# Settlement is reachable as of the shard prover's max-lag timer arm
# ---------------------------------------------------------------------------
# Until 2026-08-06 this script could not get past phase 4. Every certificate
# attempt failed `epoch close failed: Rejected(ShardCoverage)` in both aggsender
# and the aggregator, for a reason upstream of anything in this fork:
#
#   * `hyperpay_agg_program::run` requires EXACT shard coverage -- every shard in
#     the genesis topology must contribute a child to the epoch.
#   * `hyperpay-shard-prover`'s daemon loop was purely block-driven: a batch
#     closed only when the NEXT block arrived in a different epoch, so a burst of
#     payments followed by silence closed nothing at all. Measured: BOTH shard
#     provers held 0 SBPs after 200 payments.
#   * `BatchPolicy::lag_exceeded` -- the max-lag force-close that fixes exactly
#     this -- existed, was unit-tested, and had ZERO production call sites, while
#     the generated `shard-prover-<i>.toml` documented the timer as working.
#
# Fixed in the hyperpay repo: the daemon's loop is now
# `hyperpay_shard_prover::pipeline::run_loop`, a `tokio::select!` whose second
# arm ticks off `max_lag_s` and calls `lag_exceeded`. Both close paths share one
# `close_open_batch`, so the SBP is byte-identical whichever arm fired
# (`hyperpay-shard-prover/tests/lag_timer.rs`).
#
# So phases 4 and 5 are now real assertions rather than a documented stop. They
# still exit non-zero when settlement does not happen, and still print the
# rejection reason, the aggregator's counters and each prover's SBP count when
# they do -- a round-trip script that exits 0 without an L1 claim would be a lie.
#
# Full write-up, with every value read: `mvp/results/s11b-round-trip.md` in the
# hyperpay repo, sections 5 and 8.
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENCLAVE="${ENCLAVE:-hyperpay}"
ADDR_ENV="${ADDR_ENV:-${PKG_DIR}/.hyperpay-addresses.env}"
CLAIMED_ENV="${CLAIMED_ENV:-${PKG_DIR}/.hyperpay-claimed.env}"
HYPERPAY_REPO="${HYPERPAY_REPO:-/home/brolygon/repos/0xPolygon/hyperpay-wt/S11b-kurtosis-bridge-flow}"
SCENARIO_OUT="${SCENARIO_OUT:-${PKG_DIR}/.hyperpay-scenario}"

WITHDRAW_WEI="${WITHDRAW_WEI:-100000000000000000}"
PAYMENT_ROUNDS="${PAYMENT_ROUNDS:-1}"
PAYMENT_COUNT="${PAYMENT_COUNT:-20}"
REQUIRE_SETTLEMENTS="${REQUIRE_SETTLEMENTS:-3}"
SETTLE_TIMEOUT="${SETTLE_TIMEOUT:-600}"
PRIVATE_KEY="${PRIVATE_KEY:-0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
L1_RECIPIENT="${L1_RECIPIENT:-0x1111111111111111111111111111111111111111}"

log()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32mOK\033[0m  %s\n' "$*"; }
note() { printf '  \033[1;33mNOTE\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; exit 1; }

[ -r "${ADDR_ENV}" ] || die "${ADDR_ENV} missing — run scripts/hyperpay-up.sh first"
# shellcheck disable=SC1090
. "${ADDR_ENV}"

TOOL_C="$(docker ps --format '{{.Names}}' | grep -m1 "test-runner-001--")"
[ -n "${TOOL_C}" ] || die "no test-runner-001 container in the enclave"
cx() { docker exec "${TOOL_C}" "$@"; }

L1_URL="${L1_RPC}"; case "${L1_URL}" in http*) ;; *) L1_URL="http://${L1_URL}";; esac
rpc() { curl -s -m 20 "$1" -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"method\":\"$2\",\"params\":$3,\"id\":1}"; }
eth_call() { rpc "$1" eth_call "[{\"to\":\"$2\",\"data\":\"$3\"},\"latest\"]" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("result") or "")'; }
hex2dec() { python3 -c "import sys; s=sys.argv[1].strip() or '0x0'; print(int(s,16))" "$1"; }
port() { kurtosis port print "${ENCLAVE}" "$1" "$2" 2>/dev/null | tr -d '\r'; }

# ---------------------------------------------------------------------------
# 1. Deposit + claim (T7), which also writes the withdrawal cap.
# ---------------------------------------------------------------------------
if [ -z "${SKIP_DEPOSIT:-}" ]; then
  log "1/5 deposit + claim on the bridge shard (scripts/hyperpay-deposit-claim.sh)"
  "${PKG_DIR}/scripts/hyperpay-deposit-claim.sh" || die "T7 failed; the round trip cannot continue"
fi
[ -r "${CLAIMED_ENV}" ] || die "${CLAIMED_ENV} missing — T7 must run first"
# shellcheck disable=SC1090
. "${CLAIMED_ENV}"
: "${CLAIMED_WEI:?}" "${CLAIMED_DEST:?}" "${CLAIMED_TOKEN_FACADE:?}"
: "${CLAIMED_DEST_SHARD_PREFIX:?}" "${BRIDGE_INBOX_NEXT_SEQ:?}"

# THE GUARD (§1.5, ruling D6). agglayer's local balance tree credits ONLY
# claimed imported exits — never genesis and never `hp-scenario`'s synthetic
# funding, which is safe for payment liquidity precisely because transfers never
# touch the LBT. Withdrawing more than was really claimed is a `BalanceUnderflow`
# that wedges the chain in `InError` PERMANENTLY, so this is a hard assertion
# driven by a file, not a human promise.
[ "${WITHDRAW_WEI}" -le "${CLAIMED_WEI}" ] || die \
"WITHDRAW_WEI ${WITHDRAW_WEI} EXCEEDS the really-claimed ${CLAIMED_WEI}.
This is trap T-d, and it is not recoverable: agglayer's pessimistic proof credits
a network's local balance tree only from CLAIMED imported bridge exits, so an
over-large exit underflows it and leaves the chain InError permanently. Lower
WITHDRAW_WEI, or claim more first (${CLAIMED_ENV} is the only authority)."
ok "withdrawal cap: ${WITHDRAW_WEI} <= really-claimed ${CLAIMED_WEI}"

# ---------------------------------------------------------------------------
# 2. Payments across both shards, on the existing hp-scenario machinery.
#
# hp-scenario needs a WRITABLE `--out` and endpoints it can reach. `/out` in the
# enclave is a kurtosis files artifact holding ENCLAVE DNS names, so the tree is
# copied out and re-pointed at the mapped host ports. Nothing about the payment
# path is reimplemented here — E1/E2/E3 are the stock scenarios.
# ---------------------------------------------------------------------------
log "2/5 payments across both shards (hp-scenario e3, ${PAYMENT_ROUNDS} round(s) x ${PAYMENT_COUNT})"
HP_SCENARIO="${HYPERPAY_REPO}/target/release/hp-scenario"
[ -x "${HP_SCENARIO}" ] || die "${HP_SCENARIO} not built — run 'make -C ${HYPERPAY_REPO} release'"

rm -rf "${SCENARIO_OUT}"; mkdir -p "${SCENARIO_OUT}"
GW_C="$(docker ps --format '{{.Names}}' | grep -m1 'hyperpay-gateway-0-001--')"
docker cp "${GW_C}:/out/genesis" "${SCENARIO_OUT}/genesis" >/dev/null \
  || die "could not copy the generated genesis out of the gateway container"

hp() { port "$1" "$2" | sed 's#^http://##'; }
cat > "${SCENARIO_OUT}/endpoints.json" <<EOF
{
  "nats_url": "nats://$(hp hyperpay-nats-001 nats)",
  "redis_url": "redis://$(hp hyperpay-redis-001 redis)",
  "shards": [
    {"prefix":0,
     "sequencer_ingress":"http://$(hp hyperpay-sequencer-0-001 ingress)",
     "sequencer_ops":"http://$(hp hyperpay-sequencer-0-001 ops)",
     "da":"http://$(hp hyperpay-da-0-001 da)",
     "da_metrics":"http://$(hp hyperpay-da-0-001 metrics)",
     "replica":"http://$(hp hyperpay-replica-0-001 replica)",
     "replica_metrics":"http://$(hp hyperpay-replica-0-001 metrics)"},
    {"prefix":1,
     "sequencer_ingress":"http://$(hp hyperpay-sequencer-1-001 ingress)",
     "sequencer_ops":"http://$(hp hyperpay-sequencer-1-001 ops)",
     "da":"http://$(hp hyperpay-da-1-001 da)",
     "da_metrics":"http://$(hp hyperpay-da-1-001 metrics)",
     "replica":"http://$(hp hyperpay-replica-1-001 replica)",
     "replica_metrics":"http://$(hp hyperpay-replica-1-001 metrics)"}
  ],
  "gateways": [
    {"id":"gw-0","http":"http://$(hp hyperpay-gateway-0-001 http)","rpc":"http://$(hp hyperpay-gateway-0-001 rpc)","admin":"http://$(hp hyperpay-gateway-0-001 admin)"},
    {"id":"gw-1","http":"http://$(hp hyperpay-gateway-1-001 http)","rpc":"http://$(hp hyperpay-gateway-1-001 rpc)","admin":"http://$(hp hyperpay-gateway-1-001 admin)"}
  ],
  "settlement": {
    "shard_provers":[{"prefix":0,"endpoint":"http://$(hp hyperpay-shard-prover-0-001 prover)"},
                     {"prefix":1,"endpoint":"http://$(hp hyperpay-shard-prover-1-001 prover)"}],
    "bridge_rpc":"http://$(hp hyperpay-bridge-shard-001 rpc)",
    "bridge_prover":"http://$(hp hyperpay-bridge-shard-001 bridge-prover)",
    "bridge_ops":"http://$(hp hyperpay-bridge-shard-001 bridge-ops)",
    "aggregator":"http://$(hp hyperpay-aggregator-001 grpc)",
    "aggregator_metrics":"http://$(hp hyperpay-aggregator-001 metrics)"
  }
}
EOF
python3 -c "import json,sys; json.load(open('${SCENARIO_OUT}/endpoints.json'))" \
  || die "the generated endpoints.json is not valid JSON"

# Hand hp-scenario's SYNTHETIC FUNDING the bridge-inbox watermark T7 consumed,
# and then LET IT KEEP THE LEDGER. Without the seed, its first credits reuse the
# `seq_no` the real claim spent; without the persistence, every later run resets
# to 0 and reuses everything it already spent itself. Both are the same silent
# failure: an `IdempotentAck` is acked, counted as delivered, and never credited.
#
# This is not theoretical — it was measured. A run that recreated funding.json
# produced `hyperpay_sequencer_receipt_deliveries_total{class="idempotent_ack"} 7`
# on shard 0 and E3 failed with "funding never landed … replica shows 0, expected
# exactly 1000". Nothing else reports it: the receipts are acked.
#
# The ledger therefore lives OUTSIDE the per-run scenario dir, keyed on the
# enclave UUID (a new enclave starts from zero watermarks; the same enclave
# continues). hp-scenario reads and writes it in place as
# `<out>/funding.json` — this only decides its initial content and preserves it.
ENCLAVE_UUID="$(kurtosis enclave inspect "${ENCLAVE}" 2>/dev/null | awk '/^UUID:/ {print $2}')"
LEDGER="${PKG_DIR}/.hyperpay-funding-${ENCLAVE_UUID}.json"
if [ ! -r "${LEDGER}" ]; then
  python3 <<EOF
import json
json.dump({"next_seq": {"0": 0, "1": 0, "${CLAIMED_DEST_SHARD_PREFIX}": ${BRIDGE_INBOX_NEXT_SEQ}}},
          open("${LEDGER}", "w"), indent=2)
EOF
  ok "funding ledger created for enclave ${ENCLAVE_UUID}: shard ${CLAIMED_DEST_SHARD_PREFIX} starts at seq_no ${BRIDGE_INBOX_NEXT_SEQ}"
else
  ok "reusing this enclave's funding ledger: $(tr -d ' \n' < "${LEDGER}")"
fi
cp "${LEDGER}" "${SCENARIO_OUT}/funding.json"
# Copy the advanced ledger back on the way out, whatever happens next.
trap 'cp -f "${SCENARIO_OUT}/funding.json" "${LEDGER}" 2>/dev/null || true' EXIT

"${HP_SCENARIO}" e3 \
  --endpoints "${SCENARIO_OUT}/endpoints.json" \
  --l0-dir "${SCENARIO_OUT}/genesis" \
  --out "${SCENARIO_OUT}" \
  --rounds "${PAYMENT_ROUNDS}" --count "${PAYMENT_COUNT}" \
  || die "the payment phase failed (conservation, dup/loss or drop counters) — see the E3 report"
ok "payments done, per-token conservation exact (E3's own assertion)"

# ---------------------------------------------------------------------------
# 3. The withdrawal: a payment-shard bridge_exit_intent, with stock tooling.
#
# ADR-007 D8 keeps a direct `bridgeAsset` on the bridge shard a typed rejection,
# so an exit is a signed `bridgeAsset(...)` envelope sent to a GATEWAY. The ABI
# is byte-for-byte AgglayerBridge's, so `cast`/lxly.js need no change — but note
# the product difference already recorded in QUESTIONS.md: stock tooling cannot
# *initiate* a HyperPay withdrawal against the bridge shard directly.
# ---------------------------------------------------------------------------
log "3/5 withdrawing ${WITHDRAW_WEI} via bridge_exit_intent on a payment shard"
LET_BEFORE="$(curl -s -m 10 "$(port hyperpay-bridge-shard-001 bridge-ops)/metrics" \
  | awk '/^bridge_let_count/ {print $2}')"
GW_IN="http://hyperpay-gateway-${CLAIMED_DEST_SHARD_PREFIX}-001:$([ "${CLAIMED_DEST_SHARD_PREFIX}" = "0" ] && echo 8545 || echo 8555)"

# `cast send` will report "transaction was not confirmed within the timeout":
# it polls the GATEWAY for a receipt while the exit is folded on the BRIDGE
# SHARD. That is a cast artifact, not a failure — the assertions below are on
# the bridge shard's own state, which is the only thing that counts.
#
# NO `--legacy`, and as of 2026-08-06 the gateway enforces that rather than
# trusting this comment. `--legacy` makes cast emit an EIP-155 legacy envelope
# (`0xf9…`), which the in-circuit envelope decoder cannot verify (type-2 only,
# ADR-008 gap 1) and whose refusal is a FATAL shard-prover exit —
#
#   Error: Authorization("Envelope(UnsupportedType(249))")     # 249 == 0xf9
#
# — after which that shard's prover was wedged permanently: on restart it
# re-ingested the same block from height 1 and died again. Measured on a live
# enclave (shard-prover-1 Exited(1), aggregator then failing `Pull(Rpc(dns
# error))` because the container was gone).
#
# ADR-006's 2026-08-06 amendment closes that at the gateway: a legacy envelope
# for either circuit-verified kind is now refused at ingress with
# `-32000 / legacy_envelope_unprovable`, so this script could no longer wedge a
# shard even if someone re-added the flag — it would get a clean JSON-RPC error
# and fail loudly here instead. Type-2 remains ADR-006's normative envelope and
# the gateway serves `eth_maxPriorityFeePerGas`/`eth_feeHistory`, so plain
# `cast send` produces `0x02f9…` and needs no extra flag.
cx cast send "${HYPERPAY_FACADE_BRIDGE}" \
  "bridgeAsset(uint32,address,uint256,address,bool,bytes)" \
  0 "${L1_RECIPIENT}" "${WITHDRAW_WEI}" "${CLAIMED_TOKEN_FACADE}" true "0x" \
  --rpc-url "${GW_IN}" --private-key "${PRIVATE_KEY}" \
  --chain-id 4337 --gas-limit 1250000 2>&1 | tail -3

BRIDGE_TOPIC="0x501781209a1f8899323b96b4ef08b168df93e0a90c673d1e4cce39366cb62f9b"
LET_AFTER="${LET_BEFORE}"; N_EVENTS=0
for _ in $(seq 1 40); do
  LET_AFTER="$(curl -s -m 10 "$(port hyperpay-bridge-shard-001 bridge-ops)/metrics" \
    | awk '/^bridge_let_count/ {print $2}')"
  N_EVENTS="$(rpc "${L2_RPC}" eth_getLogs \
    "[{\"address\":\"${HYPERPAY_FACADE_BRIDGE}\",\"fromBlock\":\"0x0\",\"toBlock\":\"latest\",\"topics\":[\"${BRIDGE_TOPIC}\"]}]" \
    | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("result") or []))')"
  [ "${LET_AFTER:-0}" -gt "${LET_BEFORE:-0}" ] && [ "${N_EVENTS:-0}" -ge 1 ] && break
  sleep 5
done
[ "${LET_AFTER:-0}" -gt "${LET_BEFORE:-0}" ] \
  || die "no LET leaf was folded (bridge_let_count ${LET_BEFORE} -> ${LET_AFTER})"
ok "LET leaf folded on the bridge shard (bridge_let_count ${LET_BEFORE} -> ${LET_AFTER})"
[ "${N_EVENTS:-0}" -ge 1 ] || die "no BridgeEvent in eth_getLogs"
ok "${N_EVENTS} BridgeEvent(s) emitted by the facade"

# aggkit bridgesync must have indexed the exit, with a NATIVE origin — the
# registry's `(0, 0x00…00)` row is what lets L1 release ETH at all.
WD_COUNT=""; WD_ORIGIN=""
for _ in $(seq 1 40); do
  read -r WD_COUNT WD_ORIGIN <<<"$(cx curl -s -m 10 "http://${BRIDGE_REST_SVC}:5577/bridge/v1/bridges?network_id=${ROLLUP_ID}" \
    | AMT="${WITHDRAW_WEI}" TO="${L1_RECIPIENT}" python3 -c "
import sys,json,os
amt=os.environ['AMT']; to=os.environ['TO'].lower()
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
for b in d.get('bridges') or []:
    if str(b.get('amount'))==amt and str(b.get('destination_address','')).lower()==to \
       and b.get('destination_network')==0:
        print(b['deposit_count'], b.get('origin_address','')); break
")"
  [ -n "${WD_COUNT}" ] && break
  sleep 5
done
[ -n "${WD_COUNT}" ] || die "aggkit bridgesync never indexed the withdrawal"
ok "bridgesync indexed the exit: deposit_count=${WD_COUNT} origin_address=${WD_ORIGIN}"
[ "${WD_ORIGIN}" = "0x0000000000000000000000000000000000000000" ] \
  || die "the exit's origin_address is ${WD_ORIGIN}, not the native-ETH zero address —
AgglayerBridge.claimAsset on L1 would safeTransfer on that address and revert.
This is the PRESET_TOKEN_L1_ADDRESS trap; the registry ROW stamps the leaf."
ok "origin is native L1 ETH — the L1 claim in phase 5 can release value"

# ---------------------------------------------------------------------------
# 4. Settlement, asserted the T-l way: PaymentsStateUpdated count and a
#    strictly-advancing latestBlockNumber against a recorded BASELINE, never
#    getRollupExitRoot() (non-zero at startup, and unchanged per settlement).
# ---------------------------------------------------------------------------
log "4/5 waiting up to ${SETTLE_TIMEOUT}s for >= ${REQUIRE_SETTLEMENTS} settlements"
PSU_TOPIC='0xb093baec53b3de33590cc9c750af0710b04a205c4400ebc158bdd5ca847724ec'
psu_count() {
  rpc "${L1_URL}" eth_getLogs \
    "[{\"address\":\"${ROLLUP_ADDRESS}\",\"fromBlock\":\"0x0\",\"toBlock\":\"latest\",\"topics\":[\"${PSU_TOPIC}\"]}]" \
    | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("result") or []))'
}
LBN_BASE="$(hex2dec "$(eth_call "${L1_URL}" "${ROLLUP_ADDRESS}" '0x4599c788')")"
echo "  baseline latestBlockNumber = ${LBN_BASE}"
deadline=$(( $(date +%s) + SETTLE_TIMEOUT ))
count=0; lbn="${LBN_BASE}"
while [ "$(date +%s)" -lt "${deadline}" ]; do
  count="$(psu_count)"; lbn="$(hex2dec "$(eth_call "${L1_URL}" "${ROLLUP_ADDRESS}" '0x4599c788')")"
  printf '  [%s] PaymentsStateUpdated=%s latestBlockNumber=%s\n' "$(date +%T)" "${count}" "${lbn}"
  if [ "${count}" -ge "${REQUIRE_SETTLEMENTS}" ] && [ "${lbn}" -gt "${LBN_BASE}" ]; then break; fi
  sleep 15
done

if kurtosis service logs "${ENCLAVE}" agglayer 2>/dev/null | grep -qiE 'BalanceUnderflow|InError'; then
  kurtosis service logs "${ENCLAVE}" agglayer 2>/dev/null | grep -iE 'BalanceUnderflow|InError' | tail -5
  die "agglayer logged BalanceUnderflow/InError — value conservation was violated"
fi
ok "agglayer logs: no BalanceUnderflow, no InError"

if [ "${count}" -lt "${REQUIRE_SETTLEMENTS}" ] || [ "${lbn}" -le "${LBN_BASE}" ]; then
  note "lastStateRoot() = $(eth_call "${L1_URL}" "${ROLLUP_ADDRESS}" '0xb70de0d9')"
  note "aggregator: $(curl -s -m 10 "$(port hyperpay-aggregator-001 metrics)/metrics" | grep -E '^hyperpay_aggregator_(epochs_settled|polls_without_bridge_child)' | tr '\n' ' ')"
  for i in 0 1; do
    note "shard prover ${i} SBPs: $(kurtosis service logs "${ENCLAVE}" "hyperpay-shard-prover-${i}-001" 2>&1 | grep -c 'SBP retained')"
  done
  kurtosis service logs "${ENCLAVE}" hyperpay-aggregator-001 2>&1 | grep -oE 'Rejected\([A-Za-z]+\)' | sort | uniq -c | sed 's/^/  /'
  die "NOT SETTLED: ${count} PaymentsStateUpdated (want ${REQUIRE_SETTLEMENTS}), latestBlockNumber ${LBN_BASE} -> ${lbn}.

Read the two diagnostics above together:

  * Rejected(ShardCoverage) WITH a shard prover at 0 SBPs means the max-lag
    timer is not running in the image under test -- check that the deployed
    hyperpay-node image carries pipeline::run_loop ('max-lag force-close timer
    armed' is logged once at prover startup), and that max_lag_s in the
    generated shard-prover-<i>.toml is well under epoch_length_secs.
  * Rejected(ShardCoverage) with BOTH provers at >= 1 SBP is a different
    problem: the epoch the aggregator is trying to close has no child from one
    of them. Compare the retained ranges' epochs, not just their counts.
  * polls_without_bridge_child > 0 with epochs_settled 0 is the bridge child,
    not the payment shards.

Full diagnosis and the values a good run reads: mvp/results/s11b-round-trip.md
sections 5 and 8 in the hyperpay repo."
fi
ok "settled: ${count} PaymentsStateUpdated, latestBlockNumber ${LBN_BASE} -> ${lbn}"

# `lastStateRoot()` is only meaningful if it is (a) not the seeded genesis word
# and (b) EXACTLY what the aggregator committed. Both are asserted, and (b) is
# read from the aggregator's own "epoch settled" log line
# (`new_protocol_state_root`, bytes 4..36 of the `custom_chain_data` aggsender
# submitted) -- not re-derived by the thing under test.
LSR="$(eth_call "${L1_URL}" "${ROLLUP_ADDRESS}" '0xb70de0d9')"
GENESIS_ROOT="$(docker run --rm hyperpay-node:local hp-stack genesis-root --profile payments \
  2>/dev/null | tr -d '\r' | grep -oE '0x[0-9a-f]{64}' | head -1)"
[ -n "${LSR}" ] || die "lastStateRoot() returned nothing"
[ "${LSR}" != "${GENESIS_ROOT}" ] || die \
"lastStateRoot() is still the SEEDED GENESIS word ${GENESIS_ROOT} -- no
onVerifyPessimistic has written it, so the PaymentsStateUpdated count above
cannot be what it appears to be."
ok "lastStateRoot() = ${LSR} (not the seeded genesis word ${GENESIS_ROOT})"

AGG_ROOT="$(kurtosis service logs "${ENCLAVE}" hyperpay-aggregator-001 2>&1 \
  | grep 'epoch settled' | grep -oE 'new_protocol_state_root=0x[0-9a-f]{64}' \
  | tail -1 | cut -d= -f2)"
if [ -z "${AGG_ROOT}" ]; then
  die "the aggregator logged no 'epoch settled' line carrying new_protocol_state_root --
either the deployed hyperpay-node image predates that log line, or nothing
settled locally and the L1 writes above came from somewhere else. Either way the
equality below cannot be checked, and an unchecked round trip is not a round
trip."
fi
[ "${LSR}" = "${AGG_ROOT}" ] || die \
"lastStateRoot() ${LSR} != the aggregator's last committed protocol state root
${AGG_ROOT}. A real onVerifyPessimistic stores exactly the word the aggregator
put in custom_chain_data, so a mismatch means the L1 state was written by
something other than this aggregator's certificate."
ok "lastStateRoot() == the aggregator's committed protocol state root (${AGG_ROOT})"

# ---------------------------------------------------------------------------
# 5. Claim on L1 — the only thing that makes this a round trip.
# ---------------------------------------------------------------------------
log "5/5 claiming the withdrawal on L1"
pad="${L1_RECIPIENT#0x}"
L1_BAL_BEFORE="$(hex2dec "$(rpc "${L1_URL}" eth_getBalance "[\"${L1_RECIPIENT}\",\"latest\"]" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("result") or "0x0")')")"
# isClaimed(uint32,uint32) on the L1 bridge, BEFORE — the flip is the assertion.
IC_BEFORE="$(hex2dec "$(eth_call "${L1_URL}" "${L1_BRIDGE}" "0xcc461632$(printf '%064x%064x' "${WD_COUNT}" "${ROLLUP_ID}")")")"
[ "${IC_BEFORE}" = "0" ] || die "L1 isClaimed(${WD_COUNT}, ${ROLLUP_ID}) is already true"

cx polycli ulxly claim asset \
  --bridge-address "${L1_BRIDGE}" \
  --deposit-count "${WD_COUNT}" --deposit-network "${ROLLUP_ID}" \
  --destination-address "${L1_RECIPIENT}" \
  --bridge-service-url "http://${BRIDGE_REST_SVC}:5577" --legacy=false \
  --rpc-url "http://${L1_SVC}:8545" --private-key "${PRIVATE_KEY}" \
  --chain-id "$(cx cast chain-id --rpc-url "http://${L1_SVC}:8545" | tr -d '\r')" \
  --gas-limit 3000000 --wait 300s --pretty-logs=false 2>&1 | tail -6

L1_BAL_AFTER="$(hex2dec "$(rpc "${L1_URL}" eth_getBalance "[\"${L1_RECIPIENT}\",\"latest\"]" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("result") or "0x0")')")"
# The recipient is a NON-PAYER, so the delta is exact rather than gas-noisy.
[ "$(( L1_BAL_AFTER - L1_BAL_BEFORE ))" = "${WITHDRAW_WEI}" ] \
  || die "L1 balance delta $(( L1_BAL_AFTER - L1_BAL_BEFORE )) != WITHDRAW_WEI ${WITHDRAW_WEI}"
ok "L1 balance of ${L1_RECIPIENT}: ${L1_BAL_BEFORE} -> ${L1_BAL_AFTER} (delta exactly ${WITHDRAW_WEI})"
IC_AFTER="$(hex2dec "$(eth_call "${L1_URL}" "${L1_BRIDGE}" "0xcc461632$(printf '%064x%064x' "${WD_COUNT}" "${ROLLUP_ID}")")")"
[ "${IC_AFTER}" = "1" ] || die "L1 isClaimed(${WD_COUNT}, ${ROLLUP_ID}) did not flip to true"
ok "L1 isClaimed(${WD_COUNT}, ${ROLLUP_ID}): false -> true"

log "ROUND TRIP COMPLETE — L1 -> HyperPay -> payments -> HyperPay -> L1"
