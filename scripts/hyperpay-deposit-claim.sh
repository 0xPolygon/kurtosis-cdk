#!/usr/bin/env bash
# S11b T7 — an L1 deposit crosses into HyperPay and is CLAIMED on the bridge
# shard, through the real L1 bridge, the real aggkit bridge REST, and a stock
# claim submitter.
#
# Usage (needs a running enclave from scripts/hyperpay-up.sh):
#   scripts/hyperpay-deposit-claim.sh
#   DEPOSIT_WEI=2000000000000000000 scripts/hyperpay-deposit-claim.sh
#
# What it writes, and why that matters more than the log:
#   <pkg>/.hyperpay-claimed.env    CLAIMED_WEI / CLAIMED_TOKEN_FACADE /
#                                  CLAIMED_DEST / CLAIMED_DEST_SHARD_PREFIX
# T8's withdrawal cap is READ FROM THAT FILE (§1.5, orchestrator ruling D6).
# agglayer's pessimistic proof credits a network's local balance tree ONLY from
# claimed imported exits, never from genesis or synthetic balances — so a
# withdrawal larger than the really-claimed total is a `BalanceUnderflow` that
# wedges the chain in `InError` PERMANENTLY. The cap has to be mechanical.
#
# ---------------------------------------------------------------------------
# The three things that had to be true before this script could work at all
# ---------------------------------------------------------------------------
#
# 1. THE ROLLUP'S REGISTERED CHAIN ID MUST BE HYPERPAY'S.  aggkit signs its L2
#    transactions with the chain id it reads back from the RollupManager, not
#    with `eth_chainId`. Registered as kurtosis-cdk's default `2151908` against
#    a bridge shard whose genesis `chain_id` is `4337`, aggoracle's GER
#    injection is refused by the bridge shard (`wrong chain id`), aggkit's
#    ethtxmanager wedges on `failed to add tx to get monitored: already
#    exists`, and every claim below would fail `ger_not_injected` — with all 28
#    services RUNNING. Fixed in `main.star`, which overrides `l2_chain_id` from
#    `hp-stack chain-id`.
#
# 2. THE WHITELISTED TOKEN'S L1 ORIGIN MUST BE THE ZERO ADDRESS.  A native L1
#    ETH deposit is recorded as `originNetwork = 0, originTokenAddress =
#    0x00…00`, and the bridge shard resolves the credit through its genesis
#    token registry (`bridge::registry`). While the preset's token pointed at a
#    placeholder `0x…a1`, every real claim was a typed
#    `ClaimFailure::UnknownToken`. Fixed in the hyperpay repo
#    (`PRESET_TOKEN_L1_ADDRESS`), which also makes the outbound leaf claim a
#    native origin so L1 can actually release ETH in T8.
#
# 3. THE REAL CLAIM MUST OWN THE LOW END OF THE BRIDGE-INBOX SEQUENCE SPACE.
#    A payment shard imports an inbound receipt only when its `seq_no` EQUALS
#    that peer's watermark; `<` is an `IdempotentAck` — acked, counted, and
#    silently never credited. The bridge shard stamps `claim_credit` with its
#    own outbox `next_seq`, starting at 0, while `hp-scenario`'s synthetic
#    funding extends the SAME per-shard bridge-inbox chain from its
#    `funding.json` ledger. So the real claim runs FIRST and this script writes
#    the ledger T8 hands to `hp-scenario`, rather than the two racing for
#    `seq_no 0`.
#
# T-k: `curl` for host-side reads; `polycli`/`cast` run INSIDE the enclave
# toolbox container against in-network DNS.
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENCLAVE="${ENCLAVE:-hyperpay}"
ADDR_ENV="${ADDR_ENV:-${PKG_DIR}/.hyperpay-addresses.env}"
OUT_CLAIMED="${OUT_CLAIMED:-${PKG_DIR}/.hyperpay-claimed.env}"

DEPOSIT_WEI="${DEPOSIT_WEI:-1000000000000000000}"
# The kurtosis-cdk `l2_admin` key, prefunded on the local L1. We hold it, so
# T8 can also SPEND the claimed value from the credited account.
PRIVATE_KEY="${PRIVATE_KEY:-0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"

log()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32mOK\033[0m  %s\n' "$*"; }
die()  { printf '\n\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; exit 1; }

[ -r "${ADDR_ENV}" ] || die "${ADDR_ENV} missing — run scripts/hyperpay-up.sh first"
# shellcheck disable=SC1090
. "${ADDR_ENV}"
: "${ROLLUP_ID:?}" "${L1_BRIDGE:?}" "${L2_RPC:?}" "${L1_RPC:?}"
: "${HYPERPAY_FACADE_BRIDGE:?}" "${BRIDGE_REST:?}"

L1_URL="${L1_RPC}"; case "${L1_URL}" in http*) ;; *) L1_URL="http://${L1_URL}";; esac

# --- in-enclave DNS (what polycli/cast inside the toolbox use) --------------
L1_IN="http://${L1_SVC}:8545"
L2_IN="http://hyperpay-bridge-shard-001:50340"
BR_IN="http://${BRIDGE_REST_SVC}:5577"

TOOL_C="$(docker ps --format '{{.Names}}' | grep -m1 "test-runner-001--")"
[ -n "${TOOL_C}" ] || die "no test-runner-001 container in the enclave (additional_services: test_runner)"
cx() { docker exec "${TOOL_C}" "$@"; }
log "toolbox container: ${TOOL_C}"

# --- host-side JSON-RPC readers (T-k: curl, never cast) --------------------
rpc() { # rpc <url> <method> <params-json>
  curl -s -m 20 "$1" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$2\",\"params\":$3,\"id\":1}"
}
result_of() { python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("result") if d.get("result") is not None else "")' 2>/dev/null; }
eth_call() { # eth_call <url> <to> <data>
  rpc "$1" eth_call "[{\"to\":\"$2\",\"data\":\"$3\"},\"latest\"]" | result_of
}
hex2dec() { python3 -c "import sys; s=sys.argv[1].strip() or '0x0'; print(int(s,16))" "$1"; }

GW_RPC="$(kurtosis port print "${ENCLAVE}" hyperpay-gateway-0-001 rpc 2>/dev/null | tr -d '\r')"
[ -n "${GW_RPC}" ] || die "could not resolve hyperpay-gateway-0-001 rpc port"

# The credited account and the token it lands in. `balanceOf` is served by the
# gateway over the payment shard's own state, so this reads HyperPay's ledger,
# not the bridge shard's.
DEST="$(cx cast wallet address --private-key "${PRIVATE_KEY}" | tr -d '\r')"
[ -n "${DEST}" ] || die "could not derive the signer address"
TOKEN_FACADE="0x00000000000000000000000000000000000000f1"
balance_of() { # balance_of <holder>
  local pad="${1#0x}"
  hex2dec "$(eth_call "${GW_RPC}" "${TOKEN_FACADE}" "0x70a08231000000000000000000000000${pad}")"
}
# shard_prefix_bits = 1 in the 2-shard preset, so the address's TOP BIT selects
# the payment shard the credit is routed to. T8's funding ledger is keyed on it.
DEST_SHARD_PREFIX="$(python3 -c "print(1 if int('${DEST#0x}'[0:2],16) >= 0x80 else 0)")"

L1_CHAIN_ID="$(cx cast chain-id --rpc-url "${L1_IN}" 2>/dev/null | tr -d '\r')"
L2_CHAIN_ID="$(cx cast chain-id --rpc-url "${L2_IN}" 2>/dev/null | tr -d '\r')"
[ -n "${L1_CHAIN_ID}" ] && [ -n "${L2_CHAIN_ID}" ] || die "could not read both chain ids"

log "configuration"
cat <<EOF
  L1 bridge            ${L1_BRIDGE}          (chain ${L1_CHAIN_ID})
  bridge-shard facade  ${HYPERPAY_FACADE_BRIDGE}  (chain ${L2_CHAIN_ID}, network ${ROLLUP_ID})
  bridge REST          ${BR_IN}  (host ${BRIDGE_REST})
  deposit              ${DEPOSIT_WEI} wei of native L1 ETH
  credited account     ${DEST}  -> payment shard prefix ${DEST_SHARD_PREFIX}
  token facade         ${TOKEN_FACADE}
EOF

# Repeat runs against the SAME enclave accumulate; a new enclave starts over.
# Keyed on the enclave UUID because a stale file from a torn-down enclave would
# otherwise inflate T8's withdrawal cap — the one number that must never be too
# large.
ENCLAVE_UUID="$(kurtosis enclave inspect "${ENCLAVE}" 2>/dev/null | awk '/^UUID:/ {print $2}')"
PREV_WEI=0; PREV_SEQ=0
if [ -r "${OUT_CLAIMED}" ]; then
  PREV_UUID="$(awk -F= '/^CLAIMED_ENCLAVE_UUID=/ {print $2}' "${OUT_CLAIMED}")"
  PREV_DEST="$(awk -F= '/^CLAIMED_DEST=/ {print $2}' "${OUT_CLAIMED}")"
  if [ "${PREV_UUID}" = "${ENCLAVE_UUID}" ] && [ "${PREV_DEST}" = "${DEST}" ]; then
    PREV_WEI="$(awk -F= '/^CLAIMED_WEI=/ {print $2}' "${OUT_CLAIMED}")"
    PREV_SEQ="$(awk -F= '/^BRIDGE_INBOX_NEXT_SEQ=/ {print $2}' "${OUT_CLAIMED}")"
    log "accumulating onto an earlier claim in this enclave (${PREV_WEI} wei, next_seq ${PREV_SEQ})"
  fi
fi

BAL_BEFORE="$(balance_of "${DEST}")"
LET_BEFORE="$(hex2dec "$(eth_call "${L2_RPC}" "${HYPERPAY_FACADE_BRIDGE}" '0x3ae05047')")"
log "before: HyperPay balance ${BAL_BEFORE} · bridge-shard depositCount ${LET_BEFORE}"

# ---------------------------------------------------------------------------
# 1. Deposit native L1 ETH -> HyperPay.
# ---------------------------------------------------------------------------
log "1/6 depositing ${DEPOSIT_WEI} wei L1 -> HyperPay (destination network ${ROLLUP_ID})"
DEP_OUT="$(cx polycli ulxly bridge asset \
  --value "${DEPOSIT_WEI}" --gas-limit 1250000 \
  --bridge-address "${L1_BRIDGE}" --destination-address "${DEST}" \
  --destination-network "${ROLLUP_ID}" \
  --rpc-url "${L1_IN}" --private-key "${PRIVATE_KEY}" --chain-id "${L1_CHAIN_ID}" \
  --pretty-logs=false 2>&1)"
echo "${DEP_OUT}" | grep -iE 'txHash|depositCount|error' | tail -5
echo "${DEP_OUT}" | grep -qiE 'error|failed' && die "the L1 deposit did not send: $(echo "${DEP_OUT}" | tail -3)"
DEP_TX="$(echo "${DEP_OUT}" | grep -oE '0x[0-9a-fA-F]{64}' | head -1)"
[ -n "${DEP_TX}" ] || die "no deposit tx hash in polycli output"
# THIS deposit's count, from THIS transaction's own logs.
#
# Do not instead scan the REST for "the newest deposit matching (dest, amount)"
# and take the max: on a second run that max is the PREVIOUS deposit until the
# new one is indexed, and the script then happily proves a claim that already
# happened (caught exactly that way — `isClaimed is already true before
# claiming`). polycli parses the count out of the BridgeEvent it just mined.
DEP_COUNT="$(echo "${DEP_OUT}" | python3 -c 'import sys,json
n=None
for line in sys.stdin:
    line=line.strip()
    if not line.startswith("{"): continue
    try: d=json.loads(line)
    except Exception: continue
    if "depositCount" in d: n=d["depositCount"]
print("" if n is None else n)')"
[ -n "${DEP_COUNT}" ] || die "polycli did not report this deposit's depositCount:
${DEP_OUT}"
ok "L1 deposit tx ${DEP_TX} · depositCount ${DEP_COUNT}"

# ---------------------------------------------------------------------------
# 2. Wait for the deposit to become provable via the aggkit bridge REST.
# ---------------------------------------------------------------------------
log "2/6 waiting for deposit ${DEP_COUNT} to become provable (bridge REST)"
LEAF_IDX=""
for _ in $(seq 1 60); do
  INDEXED="$(cx curl -s -m 10 "${BR_IN}/bridge/v1/bridges?network_id=0" 2>/dev/null \
    | DC="${DEP_COUNT}" ME="${DEST}" NET="${ROLLUP_ID}" AMT="${DEPOSIT_WEI}" python3 -c "
import sys,json,os
dc=int(os.environ['DC']); me=os.environ['ME'].lower()
net=int(os.environ['NET']); amt=os.environ['AMT']
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for b in d.get('bridges',[]):
    if (b.get('deposit_count')==dc and b.get('destination_network')==net
            and str(b.get('destination_address','')).lower()==me
            and str(b.get('amount'))==amt):
        print('yes'); break
" 2>/dev/null | tr -d '\r')"
  if [ "${INDEXED}" = "yes" ]; then
    LEAF_IDX="$(cx curl -s -m 10 \
      "${BR_IN}/bridge/v1/l1-info-tree-index?network_id=0&deposit_count=${DEP_COUNT}" 2>/dev/null \
      | grep -oE '^[0-9]+' | head -1)"
    [ -n "${LEAF_IDX}" ] && break
  fi
  sleep 10
done
[ -n "${LEAF_IDX}" ] \
  || die "deposit ${DEP_COUNT} never became provable (indexed='${INDEXED:-no}' l1_info_tree_index='${LEAF_IDX}')"
ok "deposit_count=${DEP_COUNT} l1_info_tree_index=${LEAF_IDX}"
# Captured BEFORE the claim so the flip is asserted, not just the end state.
IS_CLAIMED_BEFORE="$(hex2dec "$(eth_call "${L2_RPC}" "${HYPERPAY_FACADE_BRIDGE}" "0xcc461632$(printf '%064x%064x' "${DEP_COUNT}" 0)")")"
[ "${IS_CLAIMED_BEFORE}" = "0" ] || die "isClaimed(${DEP_COUNT}, 0) is already true before claiming"

# ---------------------------------------------------------------------------
# 3. Claim on the BRIDGE SHARD, retrying until the covering GER is injected.
#
# The retry is not defensive padding: `claimAsset` verifies the deposit's GER
# against the GERs aggoracle has actually injected into the bridge shard's GER
# facade (`ClaimFailure::GerNotInjected`), and a fresh deposit's covering GER
# lands on aggoracle's own cadence. The precedent's e1-withdraw.sh has the same
# loop for the same reason.
# ---------------------------------------------------------------------------
log "3/6 claiming deposit ${DEP_COUNT} on the bridge shard (retrying until the GER is injected)"
claim_indexed_count() {
  cx curl -s -m 10 "${BR_IN}/bridge/v1/claims?network_id=${ROLLUP_ID}" 2>/dev/null \
    | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print(0); raise SystemExit
c=d.get("claims") or []
print(d.get("count") if isinstance(d.get("count"),int) else len(c))' 2>/dev/null | tr -d '\r'
}
CLAIM_TX=""
for attempt in $(seq 1 30); do
  CLAIM_OUT="$(cx polycli ulxly claim asset \
    --bridge-address "${HYPERPAY_FACADE_BRIDGE}" \
    --deposit-count "${DEP_COUNT}" --deposit-network 0 \
    --destination-address "${DEST}" \
    --bridge-service-url "${BR_IN}" --legacy=false \
    --rpc-url "${L2_IN}" --private-key "${PRIVATE_KEY}" --chain-id "${L2_CHAIN_ID}" \
    --gas-limit 3000000 --pretty-logs=false 2>&1)"
  CAND="$(echo "${CLAIM_OUT}" | grep -oE '0x[0-9a-fA-F]{64}' | head -1)"
  if [ -n "${CAND}" ]; then
    ST="$(rpc "${L2_RPC}" eth_getTransactionReceipt "[\"${CAND}\"]" \
      | python3 -c 'import sys,json
d=json.load(sys.stdin).get("result") or {}
print(d.get("status") or "")' 2>/dev/null)"
    if [ "${ST}" = "0x1" ]; then CLAIM_TX="${CAND}"; break; fi
    printf '  attempt %s: tx %s status %s\n' "${attempt}" "${CAND}" "${ST:-<no receipt>}"
  else
    printf '  attempt %s: %s\n' "${attempt}" "$(echo "${CLAIM_OUT}" | grep -iE 'error|ger|proof|refus' | tail -1)"
  fi
  sleep 12
done
[ -n "${CLAIM_TX}" ] || die "the claim never landed with status 1 — last output:
$(echo "${CLAIM_OUT}" | tail -12)"
ok "claimAsset tx ${CLAIM_TX} status 0x1 (mined in a real bridge-shard block)"

# ---------------------------------------------------------------------------
# 4. Assert the on-chain effects on the bridge shard.
# ---------------------------------------------------------------------------
log "4/6 asserting the bridge shard's own state"
RCPT="$(rpc "${L2_RPC}" eth_getTransactionReceipt "[\"${CLAIM_TX}\"]")"
CLAIM_BLOCK="$(echo "${RCPT}" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("result") or {}).get("blockNumber",""))')"
[ -n "${CLAIM_BLOCK}" ] || die "no blockNumber on the claim receipt"
ok "mined in bridge-shard block ${CLAIM_BLOCK} ($(hex2dec "${CLAIM_BLOCK}"))"

# DetailedClaimEvent + ClaimEvent, from the facade, by eth_getLogs.
LOGS="$(rpc "${L2_RPC}" eth_getLogs "[{\"address\":\"${HYPERPAY_FACADE_BRIDGE}\",\"fromBlock\":\"0x0\",\"toBlock\":\"latest\"}]")"
N_LOGS="$(echo "${LOGS}" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("result") or []))')"
[ "${N_LOGS:-0}" -ge 2 ] || die "expected >=2 facade logs (DetailedClaimEvent + ClaimEvent), got ${N_LOGS}
${LOGS}"
echo "${LOGS}" | python3 -c 'import sys,json
for l in json.load(sys.stdin).get("result") or []:
    print("   log topic0", (l.get("topics") or ["?"])[0], "block", l.get("blockNumber"))'
ok "${N_LOGS} facade logs emitted (DetailedClaimEvent + ClaimEvent)"

# isClaimed(uint32 leafIndex, uint32 sourceBridgeNetwork) -> bool.
# Selector 0xcc461632 — TAKEN FROM `cast sig`, not from memory: the first cut of
# this script guessed a selector, got an empty `eth_call` result, and degraded
# the assertion to a "NOTE". An unanswered view call must never read as a pass.
IC="$(eth_call "${L2_RPC}" "${HYPERPAY_FACADE_BRIDGE}" "0xcc461632$(printf '%064x%064x' "${DEP_COUNT}" 0)")"
[ -n "${IC}" ] || die "isClaimed(${DEP_COUNT}, 0) returned NOTHING — a view the facade must answer"
[ "$(hex2dec "${IC}")" = "1" ] || die "isClaimed(${DEP_COUNT}, 0) is false after a status-1 claim (${IC})"
[ "${IS_CLAIMED_BEFORE}" = "0" ] || die "isClaimed(${DEP_COUNT}, 0) was ALREADY true before this claim (${IS_CLAIMED_BEFORE})"
ok "isClaimed(${DEP_COUNT}, 0): false -> true"

# The credit itself, read through the GATEWAY (i.e. HyperPay's own ledger).
BAL_AFTER=""
for _ in $(seq 1 30); do
  BAL_AFTER="$(balance_of "${DEST}")"
  [ "${BAL_AFTER}" != "${BAL_BEFORE}" ] && break
  sleep 4
done
DELTA=$(( BAL_AFTER - BAL_BEFORE ))
[ "${DELTA}" = "${DEPOSIT_WEI}" ] \
  || die "HyperPay balance delta ${DELTA} != DEPOSIT_WEI ${DEPOSIT_WEI} (before ${BAL_BEFORE}, after ${BAL_AFTER})"
ok "HyperPay balance ${BAL_BEFORE} -> ${BAL_AFTER} (delta exactly ${DEPOSIT_WEI})"

# The RECEIPT INDIRECTION, not merely the balance: the destination payment
# shard must have APPLIED an inbound delivery, and dropped none.
SQ_OPS="$(kurtosis port print "${ENCLAVE}" "hyperpay-sequencer-${DEST_SHARD_PREFIX}-001" ops 2>/dev/null | tr -d '\r')"
APPLIED="$(curl -s -m 10 "${SQ_OPS}/metrics" | awk '/^hyperpay_sequencer_receipt_deliveries_total\{.*apply/ {print $2}' | head -1)"
DROPPED="$(curl -s -m 10 "${SQ_OPS}/metrics" | awk '/^hyperpay_sequencer_receipt_drops_total\{/ {s+=$2} END {print s+0}')"
[ -n "${APPLIED}" ] && [ "${APPLIED%.*}" -ge 1 ] \
  || die "payment shard ${DEST_SHARD_PREFIX} applied no inbound receipt — the balance moved without a claim_credit import, which is exactly what this assertion exists to catch"
[ "${DROPPED%.*}" = "0" ] \
  || die "payment shard ${DEST_SHARD_PREFIX} DROPPED ${DROPPED} inbound receipts (a dropped claim_credit is silent: see the seq_no note in this script's header)"
ok "payment shard ${DEST_SHARD_PREFIX}: ${APPLIED} inbound receipt(s) applied, ${DROPPED} dropped -> a genuine claim_credit import"

# ---------------------------------------------------------------------------
# 5. Replay must be refused, and aggkit must have indexed the claim.
# ---------------------------------------------------------------------------
log "5/6 replay rejection + aggkit claim indexing"
REPLAY_OUT="$(cx polycli ulxly claim asset \
  --bridge-address "${HYPERPAY_FACADE_BRIDGE}" \
  --deposit-count "${DEP_COUNT}" --deposit-network 0 \
  --destination-address "${DEST}" \
  --bridge-service-url "${BR_IN}" --legacy=false \
  --rpc-url "${L2_IN}" --private-key "${PRIVATE_KEY}" --chain-id "${L2_CHAIN_ID}" \
  --gas-limit 3000000 --pretty-logs=false 2>&1)"
REPLAY_TX="$(echo "${REPLAY_OUT}" | grep -oE '0x[0-9a-fA-F]{64}' | head -1)"
if [ -n "${REPLAY_TX}" ]; then
  RST="$(rpc "${L2_RPC}" eth_getTransactionReceipt "[\"${REPLAY_TX}\"]" \
    | python3 -c 'import sys,json; print((json.load(sys.stdin).get("result") or {}).get("status") or "")')"
  [ "${RST}" = "0x1" ] && die "REPLAY SUCCEEDED (${REPLAY_TX}) — the claim nullifier is not enforced"
  ok "replay refused on chain (tx ${REPLAY_TX} status ${RST:-<none>})"
else
  ok "replay refused before submission ($(echo "${REPLAY_OUT}" | grep -iE 'error|claimed' | tail -1))"
fi
BAL_REPLAY="$(balance_of "${DEST}")"
[ "${BAL_REPLAY}" = "${BAL_AFTER}" ] \
  || die "the balance changed again on replay (${BAL_AFTER} -> ${BAL_REPLAY})"
ok "balance unchanged by the replay (${BAL_REPLAY})"

N_CLAIMS=0
for _ in $(seq 1 30); do
  N_CLAIMS="$(claim_indexed_count)"
  [ "${N_CLAIMS:-0}" -ge 1 ] && break
  sleep 6
done
[ "${N_CLAIMS:-0}" -ge 1 ] || die "aggkit never indexed the claim (/bridge/v1/claims?network_id=${ROLLUP_ID} count 0)"
ok "aggkit indexed ${N_CLAIMS} claim(s) on network ${ROLLUP_ID}"

# agglayer must be clean: a BalanceUnderflow here would already be terminal.
if kurtosis service logs "${ENCLAVE}" agglayer 2>/dev/null | grep -qiE 'BalanceUnderflow|InError'; then
  kurtosis service logs "${ENCLAVE}" agglayer 2>/dev/null | grep -iE 'BalanceUnderflow|InError' | tail -5
  die "agglayer logged BalanceUnderflow/InError after the claim"
fi
ok "agglayer logs: no BalanceUnderflow, no InError"

# ---------------------------------------------------------------------------
# 6. The claimed-total file T8's withdrawal cap is driven by.
# ---------------------------------------------------------------------------
log "6/6 recording the really-claimed total"
cat > "${OUT_CLAIMED}" <<EOF
# Generated by scripts/hyperpay-deposit-claim.sh — the ONLY source of T8's
# withdrawal cap. CLAIMED_WEI is value that really entered HyperPay through a
# claimed imported bridge exit, so it is the only value agglayer's local
# balance tree will let leave again. Withdrawing more is a BalanceUnderflow
# that wedges the chain in InError permanently (trap T-d).
CLAIMED_WEI=$(( PREV_WEI + DEPOSIT_WEI ))
CLAIMED_ENCLAVE_UUID=${ENCLAVE_UUID}
CLAIMED_DEST=${DEST}
CLAIMED_DEST_SHARD_PREFIX=${DEST_SHARD_PREFIX}
CLAIMED_TOKEN_FACADE=${TOKEN_FACADE}
CLAIMED_DEPOSIT_COUNT=${DEP_COUNT}
CLAIMED_DEPOSIT_TX=${DEP_TX}
CLAIMED_CLAIM_TX=${CLAIM_TX}
CLAIMED_CLAIM_BLOCK=${CLAIM_BLOCK}
# Where hp-scenario's synthetic funding must START on this shard's BRIDGE inbox
# chain. Taken from the destination sequencer's own applied-inbound-delivery
# counter rather than from a count this script keeps: it is the shard's real
# watermark, it self-corrects across repeated runs, and it cannot drift.
#
# Valid because T7 runs BEFORE any payment traffic, so every applied inbound
# delivery on this shard so far is a claim_credit from the bridge peer. Funding
# that reuses a consumed seq_no is an IdempotentAck — acked, counted as
# delivered, and silently never credited (this script's header, point 3).
BRIDGE_INBOX_NEXT_SEQ=${APPLIED%.*}
EOF
cat "${OUT_CLAIMED}"
ok "wrote ${OUT_CLAIMED}"

log "T7 GREEN — real value crossed L1 -> HyperPay and was claimed on the bridge shard"
