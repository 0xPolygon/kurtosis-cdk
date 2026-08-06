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
#   START_PHASE=4 scripts/hyperpay-round-trip.sh     # resume at the settlement wait
#
# START_PHASE exists because the settlement wait is the long pole (default
# SETTLE_TIMEOUT=600s, and the honest value for >= 3 epochs at a 60 s bridge
# epoch is larger) and because re-running phases 1-3 to get back to it would
# deposit, pay and WITHDRAW a second time — a second exit that phase 5 would
# then confuse with the first. Phase 3 therefore records the withdrawal it made
# in <pkg>/.hyperpay-withdrawal.env, and START_PHASE=4 resumes from that exact
# exit. Resuming never re-withdraws.
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
#
# ---------------------------------------------------------------------------
# THE TRAFFIC IN PHASE 4 IS LOAD-BEARING, NOT DECORATIVE
# ---------------------------------------------------------------------------
# Read this before lowering `PHASE4_TRICKLE_PER_TICK` to 0 to "speed the run up".
#
# `hyperpay_agg_program::run` requires EXACT shard coverage: every shard in the
# genesis topology must contribute a child to the epoch being folded. A payment
# shard contributes a child only if its prover has an SBP, and its prover has an
# SBP only if the sequencer sealed a block — and an IDLE payment shard seals
# nothing at all. There is no empty-block heartbeat on a payment shard.
#
# So this script used to assert something the design cannot do. It sent one burst
# of payments up front, then waited up to `SETTLE_TIMEOUT` in silence for
# `REQUIRE_SETTLEMENTS` epochs. The burst covers ONE epoch; every later epoch has
# two idle payment shards and is refused. Measured on the 2026-08-06 run: 457
# `Rejected(ShardCoverage)` refusals during a silent wait. That count was not a
# defect report — it was the design correctly refusing to fold epochs that had no
# payment blocks in them.
#
# Phase 4 therefore sends a steady trickle for the WHOLE duration of the wait,
# interleaved with the L1 polling (one batch per poll tick, both directions,
# through both gateways) rather than backgrounded — so it cannot outlive the
# script and cannot silently stop. Every epoch the wait crosses then has real
# blocks on both payment shards to cover.
#
# Two properties the trickle must keep, and does:
#
#   * every wei it moves still traces to the REAL claim from phase 1 — it moves
#     value between two keyed accounts, one per shard, and mints nothing. A
#     synthetic `ClaimCredit` would be a forged mint (see phase 2's header) and
#     would wedge settlement permanently.
#   * it never eats into `WITHDRAW_WEI`. The whole window's spend is bounded up
#     front and asserted against the claimed balance minus the withdrawal.
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENCLAVE="${ENCLAVE:-hyperpay}"
ADDR_ENV="${ADDR_ENV:-${PKG_DIR}/.hyperpay-addresses.env}"
CLAIMED_ENV="${CLAIMED_ENV:-${PKG_DIR}/.hyperpay-claimed.env}"
WITHDRAWAL_ENV="${WITHDRAWAL_ENV:-${PKG_DIR}/.hyperpay-withdrawal.env}"
START_PHASE="${START_PHASE:-1}"
HYPERPAY_REPO="${HYPERPAY_REPO:-/home/brolygon/repos/0xPolygon/hyperpay-wt/S11b-kurtosis-bridge-flow}"
SCENARIO_OUT="${SCENARIO_OUT:-${PKG_DIR}/.hyperpay-scenario}"

WITHDRAW_WEI="${WITHDRAW_WEI:-100000000000000000}"
PAYMENT_ROUNDS="${PAYMENT_ROUNDS:-1}"
PAYMENT_COUNT="${PAYMENT_COUNT:-20}"
REQUIRE_SETTLEMENTS="${REQUIRE_SETTLEMENTS:-3}"
# Which payment phase runs (see phase 2's header for why this exists at all):
#   e3            hp-scenario e3 — the stock scenario, SYNTHETICALLY funded.
#                 Exercises the payment path hardest, but cannot settle: see below.
#   claimed-only  cross-shard transfers out of the REALLY-CLAIMED address only.
#                 Weaker payment coverage, but every wei on both shards traces to
#                 a claimed imported bridge exit, so the fold is sound.
PAYMENTS_MODE="${PAYMENTS_MODE:-e3}"
CLAIMED_ONLY_COUNT="${CLAIMED_ONLY_COUNT:-10}"
CLAIMED_ONLY_WEI="${CLAIMED_ONLY_WEI:-10000000000000000}"
SETTLE_TIMEOUT="${SETTLE_TIMEOUT:-600}"
# Phase 4's sustained traffic (see the header: it is what gives each epoch in the
# settlement window blocks to cover). One batch per poll tick, both directions.
PHASE4_POLL_SECS="${PHASE4_POLL_SECS:-15}"
PHASE4_TRICKLE_PER_TICK="${PHASE4_TRICKLE_PER_TICK:-2}"
PHASE4_TRICKLE_WEI="${PHASE4_TRICKLE_WEI:-1000000000000000}"
# The cross-shard counterparty is a KEYED account, not a bare address, because
# phase 4 needs it to send as well as receive — that is what puts traffic through
# BOTH gateways instead of one. Its address is derived at run time (never
# hard-coded as a derived value) and asserted to live on the other shard.
CO_PAYEE_KEY="${CO_PAYEE_KEY:-0x00000000000000000000000000000000000000000000000000000000000a11d2}"
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
if [ -z "${SKIP_DEPOSIT:-}" ] && [ "${START_PHASE}" -le 1 ]; then
  log "1/5 deposit + claim on the bridge shard (scripts/hyperpay-deposit-claim.sh)"
  "${PKG_DIR}/scripts/hyperpay-deposit-claim.sh" || die "T7 failed; the round trip cannot continue"
else
  log "1/5 SKIPPED (START_PHASE=${START_PHASE}) — reusing the recorded claim"
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
# The cross-shard counterparty and the per-shard gateway map, shared by phase 2
# (claimed-only) and phase 4 (the sustained trickle).
#
# With `shard_prefix_bits = 1` a shard IS the address's top bit, so 0x10.. is
# shard 0 and 0xE3.. (the claimed address) is shard 1. Both facts are asserted
# rather than assumed: a preset with more prefix bits would silently make every
# transfer same-shard, starving one shard of SBPs — which reads as
# `Rejected(ShardCoverage)` and looks like a settlement bug.
# ---------------------------------------------------------------------------
co_shard() { python3 -c 'import sys; print(int(sys.argv[1],16) >> (160-1))' "$1"; }
gw_of() { case "$1" in 0) echo "http://hyperpay-gateway-0-001:8545";; *) echo "http://hyperpay-gateway-1-001:8555";; esac; }

CO_PAYEE="${CO_PAYEE:-$(cx cast wallet address --private-key "${CO_PAYEE_KEY}" | tr -d '\r')}"
[ -n "${CO_PAYEE}" ] || die "could not derive an address from CO_PAYEE_KEY"
CO_PAYEE_SHARD="$(co_shard "${CO_PAYEE}")"
CLAIMED_SHARD="$(co_shard "${CLAIMED_DEST}")"
[ "${CO_PAYEE_SHARD}" != "${CLAIMED_SHARD}" ] || die \
"the counterparty ${CO_PAYEE} is on the SAME shard (${CO_PAYEE_SHARD}) as the
claimed address ${CLAIMED_DEST}. Every transfer would then be same-shard, one
shard would seal no blocks, its prover would hold no SBP, and the fold would
refuse every epoch as ShardCoverage. Pick a CO_PAYEE_KEY whose address is on the
other shard."
[ "${CLAIMED_SHARD}" = "${CLAIMED_DEST_SHARD_PREFIX}" ] || die \
"the claimed address ${CLAIMED_DEST} derives to shard ${CLAIMED_SHARD} but T7
recorded CLAIMED_DEST_SHARD_PREFIX=${CLAIMED_DEST_SHARD_PREFIX}. The preset's
shard_prefix_bits is not 1, so this script's shard arithmetic is wrong."
ok "counterparty ${CO_PAYEE} on shard ${CO_PAYEE_SHARD}, payer ${CLAIMED_DEST} on shard ${CLAIMED_SHARD} — cross-shard, and both are keyed"

# Phase 4's whole-window spend, bounded UP FRONT so the withdrawal can never be
# eaten by traffic. One batch per poll tick, per direction, for the full timeout.
PHASE4_TICKS=$(( SETTLE_TIMEOUT / PHASE4_POLL_SECS + 1 ))
PHASE4_BUDGET=$(( PHASE4_TICKS * PHASE4_TRICKLE_PER_TICK * PHASE4_TRICKLE_WEI ))
ok "phase 4 trickle: <= ${PHASE4_TICKS} ticks x ${PHASE4_TRICKLE_PER_TICK} x ${PHASE4_TRICKLE_WEI} = ${PHASE4_BUDGET} wei per direction"

# ---------------------------------------------------------------------------
# 2. Payments across both shards.
#
# TWO MODES, because the stock one provably cannot settle. Measured 2026-08-06,
# on a clean bring-up with BOTH of that day's fixes in (the genesis bridge leaf
# and the gateway's legacy refusal): phases 1-3 pass, and then EVERY certificate
# attempt is refused
#
#   epoch close failed error=Rejected(InboxAheadOfOutbox {
#       src: ShardPrefix { bits: [171, 192, 0, ...], len: 12 },   # the bridge shard
#       dst: ShardPrefix { bits: [0, 0, 0, ...],     len: 1  } }) # payment shard 0
#
# `hyperpay_agg_program::run`'s FORGED-MINT check (`run.rs`: `if seq_i > o.0`)
# refuses an epoch in which a payment shard's inbox for the `(bridge -> shard)`
# pair is ahead of the bridge shard's own outbox for it. `hyperpay_e2e::fund`
# credits payers by injecting a `ClaimCredit` receipt onto exactly that inbox
# chain, signed with the bridge shard's key — so it advances the INBOX while the
# real bridge shard's OUTBOX never moves. E3's own log says it plainly:
#
#   E3: funded 11 payer(s) on shard 0 (seq 0..11)
#   E3: funded  9 payer(s) on shard 1 (seq 1..10)
#
# and shard 0 never received a real claim at all, so its bridge outbox is 0.
# 11 > 0, forever: the inbox watermark never goes down, so once funding has run,
# THAT ENCLAVE CAN NEVER SETTLE.
#
# This is not a bug in `fund` and not a bug in the check. It is S11b §1.5 /
# ruling D6 ("keep synthetic `fund`... transfers never touch agglayer's local
# balance tree") meeting a rule it was never checked against: the justification
# is about AGGLAYER's local balance tree, and it is correct about that — but
# HyperPay's OWN aggregation statement has a forged-mint rule on the
# bridge->payment queue pair, and a synthetic `ClaimCredit` is formally a forged
# mint. Both components are behaving exactly as documented.
#
# So `PAYMENTS_MODE` picks which property this run is asserting:
#
#   e3            the stock scenario, synthetically funded. Hardest payment
#                 coverage; settlement is unreachable, by construction.
#   claimed-only  every wei that moves traces to the REAL claim from phase 1.
#                 Cross-shard transfers out of the claimed address give BOTH
#                 shards sealed blocks (burn on the payer's shard, mint leg on
#                 the payee's) with a real outbox delta behind every inbox
#                 advance, so the fold has nothing to refuse.
#
# hp-scenario needs a WRITABLE `--out` and endpoints it can reach. `/out` in the
# enclave is a kurtosis files artifact holding ENCLAVE DNS names, so the tree is
# copied out and re-pointed at the mapped host ports. Nothing about the payment
# path is reimplemented here — E1/E2/E3 are the stock scenarios.
# ---------------------------------------------------------------------------
CO_TOTAL=0
if [ "${START_PHASE}" -gt 2 ]; then
  log "2/5 SKIPPED (START_PHASE=${START_PHASE})"
elif [ "${PAYMENTS_MODE}" = "claimed-only" ]; then
  log "2/5 payments: ${CLAIMED_ONLY_COUNT} cross-shard transfers of ${CLAIMED_ONLY_WEI} out of the REALLY-CLAIMED address (no synthetic funding)"

  # The payee is the shared keyed counterparty derived above: on the OTHER
  # shard, so every transfer is cross-shard and both shards seal blocks — and
  # keyed, so phase 4 can send value back through the other gateway.
  #
  # Leave the withdrawal AND phase 4's whole trickle budget covered. Moving out
  # more than that would make phase 3's burn, or phase 4's traffic, fail on
  # balance rather than on anything interesting.
  CO_TOTAL=$(( CLAIMED_ONLY_COUNT * CLAIMED_ONLY_WEI ))
  [ "$(( CO_TOTAL + WITHDRAW_WEI + PHASE4_BUDGET ))" -le "${CLAIMED_WEI}" ] || die \
"claimed-only would move ${CO_TOTAL} out of the claimed ${CLAIMED_WEI}, leaving
less than WITHDRAW_WEI ${WITHDRAW_WEI} plus phase 4's trickle budget
${PHASE4_BUDGET} for phases 3 and 4. Lower CLAIMED_ONLY_COUNT."
  # Phase 4's return leg spends from the counterparty, so phase 2 must leave it
  # enough to send: this is the reason CO_TOTAL is not simply "as much as
  # possible".
  [ "${CO_TOTAL}" -ge "${PHASE4_BUDGET}" ] || note \
    "phase 2 moves ${CO_TOTAL} to the counterparty, less than phase 4's ${PHASE4_BUDGET} budget — its return leg will stop early"

  GW_PAY="$(gw_of "${CLAIMED_DEST_SHARD_PREFIX}")"

  # `--async` and an EXPLICIT nonce, both deliberate:
  #
  #  * `--async` submits and returns the hash. Without it `cast` polls the
  #    GATEWAY for a receipt while a cross-shard payment finalizes on the
  #    PAYEE's shard, so every send would burn its full timeout for nothing
  #    (phase 3 documents the same artifact for the exit).
  #  * the nonce is read ONCE and then incremented locally. `cast` otherwise
  #    asks the gateway per send, and the gateway answers from the read
  #    replica — which lags a few blocks behind, so a burst would hand the
  #    same nonce to several sends and the sequencer would refuse all but one
  #    on its nonce window. Nothing would report it except a short balance.
  CO_NONCE0="$(cx cast nonce "${CLAIMED_DEST}" --rpc-url "${GW_PAY}" 2>/dev/null | tr -d '\r')"
  case "${CO_NONCE0}" in ''|*[!0-9]*) CO_NONCE0=0 ;; esac
  echo "  starting nonce for ${CLAIMED_DEST}: ${CO_NONCE0}"
  co_sent=0
  i=0
  while [ "${i}" -lt "${CLAIMED_ONLY_COUNT}" ]; do
    if cx cast send "${CLAIMED_TOKEN_FACADE}" "transfer(address,uint256)" \
         "${CO_PAYEE}" "${CLAIMED_ONLY_WEI}" \
         --rpc-url "${GW_PAY}" --private-key "${PRIVATE_KEY}" \
         --chain-id 4337 --gas-limit 1250000 \
         --nonce "$(( CO_NONCE0 + i ))" --async >/dev/null 2>&1; then
      co_sent=$(( co_sent + 1 ))
    fi
    i=$(( i + 1 ))
  done
  note "${co_sent}/${CLAIMED_ONLY_COUNT} transfers submitted (nonces ${CO_NONCE0}..$(( CO_NONCE0 + CLAIMED_ONLY_COUNT - 1 )))"
  [ "${co_sent}" -gt 0 ] || die "not one transfer was accepted by the gateway"

  # The real assertion: the cross-shard payee is credited, read off the OTHER
  # shard's gateway.
  GW_OTHER="$(gw_of "${CO_PAYEE_SHARD}")"
  CO_BAL=0
  for _ in $(seq 1 24); do
    CO_BAL="$(cx cast call "${CLAIMED_TOKEN_FACADE}" "balanceOf(address)(uint256)" \
      "${CO_PAYEE}" --rpc-url "${GW_OTHER}" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
    case "${CO_BAL}" in ''|*[!0-9]*) CO_BAL=0 ;; esac
    [ "${CO_BAL}" -gt 0 ] && break
    sleep 5
  done
  [ "${CO_BAL}" -gt 0 ] || die \
"the cross-shard payee ${CO_PAYEE} was never credited (balanceOf = 0 on the
payee's own shard). No value moved, so there is nothing for the fold to prove."
  ok "cross-shard payee credited: balanceOf(${CO_PAYEE}) = ${CO_BAL} on its own shard"
  ok "every wei that moved traces to the real claim — no synthetic bridge credit exists on this enclave"
else
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
note "PAYMENTS_MODE=e3 uses SYNTHETIC funding; settlement in phase 4 is unreachable by construction (see phase 2's header)"
fi

# ---------------------------------------------------------------------------
# 3. The withdrawal: a payment-shard bridge_exit_intent, with stock tooling.
#
# ADR-007 D8 keeps a direct `bridgeAsset` on the bridge shard a typed rejection,
# so an exit is a signed `bridgeAsset(...)` envelope sent to a GATEWAY. The ABI
# is byte-for-byte AgglayerBridge's, so `cast`/lxly.js need no change — but note
# the product difference already recorded in QUESTIONS.md: stock tooling cannot
# *initiate* a HyperPay withdrawal against the bridge shard directly.
# ---------------------------------------------------------------------------
if [ "${START_PHASE}" -gt 3 ]; then
log "3/5 SKIPPED (START_PHASE=${START_PHASE}) — reusing the recorded withdrawal"
[ -r "${WITHDRAWAL_ENV}" ] || die "${WITHDRAWAL_ENV} missing — phase 3 must have run once
before START_PHASE=4 can resume from its exit. Resuming must never re-withdraw."
# shellcheck disable=SC1090
. "${WITHDRAWAL_ENV}"
: "${WD_COUNT:?}" "${WD_ORIGIN:?}"
ok "resuming from the recorded exit: deposit_count=${WD_COUNT} origin_address=${WD_ORIGIN}"
else
log "3/5 withdrawing ${WITHDRAW_WEI} via bridge_exit_intent on a payment shard"
LET_BEFORE="$(curl -s -m 10 "$(port hyperpay-bridge-shard-001 bridge-ops)/metrics" \
  | awk '/^bridge_let_count/ {print $2}')"
GW_IN="$(gw_of "${CLAIMED_DEST_SHARD_PREFIX}")"

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

# Record the exit so START_PHASE=4 can resume against THIS withdrawal instead of
# making a second one (see the usage note at the top).
cat > "${WITHDRAWAL_ENV}" <<EOF
# Generated by scripts/hyperpay-round-trip.sh phase 3 — the exit phase 5 claims.
WD_COUNT=${WD_COUNT}
WD_ORIGIN=${WD_ORIGIN}
WD_AMOUNT=${WITHDRAW_WEI}
WD_RECIPIENT=${L1_RECIPIENT}
EOF
ok "exit recorded in ${WITHDRAWAL_ENV} (START_PHASE=4 resumes from it, never re-withdrawing)"
fi

# ---------------------------------------------------------------------------
# 4. Settlement, asserted the T-l way: PaymentsStateUpdated count and a
#    strictly-advancing latestBlockNumber against a recorded BASELINE, never
#    getRollupExitRoot() (non-zero at startup, and unchanged per settlement).
#
#    WITH SUSTAINED TRAFFIC FOR THE WHOLE WAIT — see this file's header. An idle
#    payment shard seals no block, so an epoch spanning an idle window has no
#    payment child and `run` refuses it as ShardCoverage. Waiting in silence for
#    N settlements is therefore asking the design for something it cannot do; the
#    457 ShardCoverage refusals the previous run recorded were that refusal, not
#    a defect. Each poll tick below sends a small batch BOTH ways between the two
#    keyed accounts, so every epoch the wait crosses has real blocks on both
#    payment shards, and every wei still traces to phase 1's real claim.
# ---------------------------------------------------------------------------
log "4/5 waiting up to ${SETTLE_TIMEOUT}s for >= ${REQUIRE_SETTLEMENTS} settlements, with a trickle of traffic throughout"
PSU_TOPIC='0xb093baec53b3de33590cc9c750af0710b04a205c4400ebc158bdd5ca847724ec'
psu_count() {
  rpc "${L1_URL}" eth_getLogs \
    "[{\"address\":\"${ROLLUP_ADDRESS}\",\"fromBlock\":\"0x0\",\"toBlock\":\"latest\",\"topics\":[\"${PSU_TOPIC}\"]}]" \
    | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("result") or []))'
}
sbp_count() { kurtosis service logs "${ENCLAVE}" "hyperpay-shard-prover-$1-001" 2>&1 | grep -c 'SBP retained'; }

GW_A="$(gw_of "${CLAIMED_SHARD}")"      # the claimed payer's own gateway
GW_B="$(gw_of "${CO_PAYEE_SHARD}")"     # the counterparty's own gateway
bal_of() { # bal_of <addr> <gateway>
  local v
  v="$(cx cast call "${CLAIMED_TOKEN_FACADE}" "balanceOf(address)(uint256)" "$1" \
        --rpc-url "$2" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
  case "${v}" in ''|*[!0-9]*) echo 0 ;; *) echo "${v}" ;; esac
}

# The nonce discipline from phase 2, made resilient across a long window: the
# gateway answers `eth_getTransactionCount` from the READ REPLICA, which lags,
# so a tick that trusted it alone would reuse a nonce it already spent and the
# sequencer would drop the duplicate with nothing to report but a short balance.
# Each side therefore keeps a local high-water mark and uses max(read, local+1).
A_NEXT=0; B_NEXT=0
# `send_leg` reports through the global LEG_SENT rather than stdout on purpose:
# `$(send_leg ...)` would run it in a SUBSHELL, and the nonce high-water mark it
# advances would be lost every tick — handing the same nonce out over and over.
LEG_SENT=0
send_leg() { # send_leg <from_key> <from_addr> <to_addr> <gateway> <nonce_var_name>
  local key="$1" from="$2" to="$3" gw="$4" nvar="$5" read_n n=0 i=0
  read_n="$(cx cast nonce "${from}" --rpc-url "${gw}" 2>/dev/null | tr -d '\r')"
  case "${read_n}" in ''|*[!0-9]*) read_n=0 ;; esac
  if [ "${read_n}" -gt "${!nvar}" ]; then printf -v "${nvar}" '%s' "${read_n}"; fi
  while [ "${i}" -lt "${PHASE4_TRICKLE_PER_TICK}" ]; do
    if cx cast send "${CLAIMED_TOKEN_FACADE}" "transfer(address,uint256)" \
         "${to}" "${PHASE4_TRICKLE_WEI}" \
         --rpc-url "${gw}" --private-key "${key}" --chain-id 4337 --gas-limit 1250000 \
         --nonce "${!nvar}" --async >/dev/null 2>&1; then
      n=$(( n + 1 ))
    fi
    printf -v "${nvar}" '%s' "$(( ${!nvar} + 1 ))"
    i=$(( i + 1 ))
  done
  LEG_SENT="${n}"
}

SBP0_BASE="$(sbp_count 0)"; SBP1_BASE="$(sbp_count 1)"
BAL_A_BASE="$(bal_of "${CLAIMED_DEST}" "${GW_A}")"
BAL_B_BASE="$(bal_of "${CO_PAYEE}" "${GW_B}")"
echo "  baseline SBPs retained: shard 0 = ${SBP0_BASE}, shard 1 = ${SBP1_BASE}"
echo "  baseline balances: payer ${BAL_A_BASE}, counterparty ${BAL_B_BASE}"
# The return leg only runs while the counterparty can actually pay. Said out
# loud rather than discovered as silently-dropped sends.
RETURN_LEG=1
if [ "${BAL_B_BASE}" -lt "$(( PHASE4_TRICKLE_PER_TICK * PHASE4_TRICKLE_WEI ))" ]; then
  RETURN_LEG=0
  note "the counterparty holds ${BAL_B_BASE} — too little to send, so this window's traffic is one-directional (still cross-shard, so both shards still seal blocks)"
fi

LBN_BASE="$(hex2dec "$(eth_call "${L1_URL}" "${ROLLUP_ADDRESS}" '0x4599c788')")"
echo "  baseline latestBlockNumber = ${LBN_BASE}"
deadline=$(( $(date +%s) + SETTLE_TIMEOUT ))
count=0; lbn="${LBN_BASE}"; sent_a=0; sent_b=0; ticks=0
while [ "$(date +%s)" -lt "${deadline}" ]; do
  # Traffic FIRST, then read L1: a tick that polled and broke out early would
  # otherwise leave the last epoch of the window without blocks.
  send_leg "${PRIVATE_KEY}" "${CLAIMED_DEST}" "${CO_PAYEE}" "${GW_A}" A_NEXT
  n_a="${LEG_SENT}"; sent_a=$(( sent_a + n_a )); n_b=0
  if [ "${RETURN_LEG}" = "1" ] \
     && [ "$(bal_of "${CO_PAYEE}" "${GW_B}")" -ge "$(( PHASE4_TRICKLE_PER_TICK * PHASE4_TRICKLE_WEI ))" ]; then
    send_leg "${CO_PAYEE_KEY}" "${CO_PAYEE}" "${CLAIMED_DEST}" "${GW_B}" B_NEXT
    n_b="${LEG_SENT}"; sent_b=$(( sent_b + n_b ))
  fi
  ticks=$(( ticks + 1 ))

  count="$(psu_count)"; lbn="$(hex2dec "$(eth_call "${L1_URL}" "${ROLLUP_ADDRESS}" '0x4599c788')")"
  printf '  [%s] PaymentsStateUpdated=%s latestBlockNumber=%s  (tick %s: %s->%s %s, %s->%s %s)\n' \
    "$(date +%T)" "${count}" "${lbn}" "${ticks}" \
    "${CLAIMED_SHARD}" "${CO_PAYEE_SHARD}" "${n_a}" \
    "${CO_PAYEE_SHARD}" "${CLAIMED_SHARD}" "${n_b}"
  if [ "${count}" -ge "${REQUIRE_SETTLEMENTS}" ] && [ "${lbn}" -gt "${LBN_BASE}" ]; then break; fi
  sleep "${PHASE4_POLL_SECS}"
done

# The traffic has to have been real, or the wait above proved nothing about
# coverage. Both are asserted from the components' own state, not from the send
# count: an accepted `cast send` only means the gateway took the envelope.
SBP0_AFTER="$(sbp_count 0)"; SBP1_AFTER="$(sbp_count 1)"
note "traffic over ${ticks} tick(s): ${sent_a} sends shard ${CLAIMED_SHARD}->${CO_PAYEE_SHARD}, ${sent_b} sends shard ${CO_PAYEE_SHARD}->${CLAIMED_SHARD}"
note "SBPs retained: shard 0 ${SBP0_BASE} -> ${SBP0_AFTER}, shard 1 ${SBP1_BASE} -> ${SBP1_AFTER}"
[ "${sent_a}" -gt 0 ] || die "not one trickle transfer was accepted during the settlement window —
the wait was silent, so every epoch it spans has idle payment shards and
ShardCoverage is the CORRECT refusal. Fix the traffic, not the fold."
if [ "${SBP0_AFTER}" -le "${SBP0_BASE}" ] || [ "${SBP1_AFTER}" -le "${SBP1_BASE}" ]; then
  die "a payment shard sealed nothing during the settlement window (shard 0 ${SBP0_BASE} -> ${SBP0_AFTER},
shard 1 ${SBP1_BASE} -> ${SBP1_AFTER}). The trickle reached the gateway but did not
become blocks on both shards, so exact shard coverage is unreachable and any
ShardCoverage refusal below is a consequence of that, not of the fold."
fi
ok "both payment shards sealed blocks throughout the window — every epoch in it had children to cover"

if kurtosis service logs "${ENCLAVE}" agglayer 2>/dev/null | grep -qiE 'BalanceUnderflow|InError'; then
  kurtosis service logs "${ENCLAVE}" agglayer 2>/dev/null | grep -iE 'BalanceUnderflow|InError' | tail -5
  die "agglayer logged BalanceUnderflow/InError — value conservation was violated"
fi
ok "agglayer logs: no BalanceUnderflow, no InError"

if [ "${count}" -lt "${REQUIRE_SETTLEMENTS}" ] || [ "${lbn}" -le "${LBN_BASE}" ]; then
  note "lastStateRoot() = $(eth_call "${L1_URL}" "${ROLLUP_ADDRESS}" '0xb70de0d9')"
  note "aggregator: $(curl -s -m 10 "$(port hyperpay-aggregator-001 metrics)/metrics" | grep -E '^hyperpay_aggregator_(epochs_settled|polls_without_bridge_child|proofs_served_from_retained)' | tr '\n' ' ')"
  note "aggsender: $(kurtosis service logs "${ENCLAVE}" aggkit 2>&1 | grep -ciE 'no epoch is currently closable') requests answered 'no epoch is currently closable'"
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
  * epochs_settled >= 1 with 0 PaymentsStateUpdated means the epoch settled
    LOCALLY and never became a certificate. Check proofs_served_from_retained:
    if it is 0 while epochs_settled rises, aggsender is not reaching this
    aggregator at all; if it rises too, the certificate is being built and the
    refusal is on agglayer's side, not here.
  * Rejected(ShardCoverage) with both provers advancing AND traffic asserted
    above is the epoch-ATTRIBUTION problem, not a coverage one: per-shard
    sealing clocks are independent (each payment prover has its own max-lag
    timer, the bridge shard has a wall-clock epoch), and this driver attributes
    every unacked payment SBP to the epoch of the FIRST new bridge range
    (bridge_new.first()). That is a
    protocol question, not a script one -- see ADR-009 and
    plans/S11b-kurtosis-bridge-flow.md's 2026-08-06 section.

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

CLAIM_LOG="${SCENARIO_OUT}.claim.log"
mkdir -p "$(dirname "${CLAIM_LOG}")" 2>/dev/null || true
cx polycli ulxly claim asset \
  --bridge-address "${L1_BRIDGE}" \
  --deposit-count "${WD_COUNT}" --deposit-network "${ROLLUP_ID}" \
  --destination-address "${L1_RECIPIENT}" \
  --bridge-service-url "http://${BRIDGE_REST_SVC}:5577" --legacy=false \
  --rpc-url "http://${L1_SVC}:8545" --private-key "${PRIVATE_KEY}" \
  --chain-id "$(cx cast chain-id --rpc-url "http://${L1_SVC}:8545" | tr -d '\r')" \
  --gas-limit 3000000 --wait 300s --pretty-logs=false 2>&1 | tee "${CLAIM_LOG}" | tail -6

# The claim's own L1 receipt must say `status: 1`. The balance delta and the
# isClaimed flip below are the stronger facts, but a reverted claimAsset that
# happened to coincide with either would otherwise read as a pass — and the
# receipt is one `curl` away, trusting no HyperPay component.
CLAIM_TX="$(grep -oE '0x[0-9a-fA-F]{64}' "${CLAIM_LOG}" | tail -1)"
if [ -n "${CLAIM_TX}" ]; then
  CLAIM_STATUS="$(rpc "${L1_URL}" eth_getTransactionReceipt "[\"${CLAIM_TX}\"]" \
    | python3 -c 'import sys,json; r=json.load(sys.stdin).get("result") or {}; print(r.get("status") or "")')"
  [ "${CLAIM_STATUS}" = "0x1" ] || die \
"the L1 claimAsset receipt ${CLAIM_TX} has status ${CLAIM_STATUS:-<none>}, not 0x1 —
a reverted claim cannot be a round trip, whatever the balances say."
  ok "L1 claimAsset ${CLAIM_TX} receipt status = 0x1"
else
  die "no L1 transaction hash in polycli's output — nothing to read a receipt for.
See ${CLAIM_LOG}."
fi

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
