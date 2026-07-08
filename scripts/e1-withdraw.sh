#!/usr/bin/env bash
#
# e1-withdraw.sh — exercise a full deposit -> claim -> (<=deposit) withdrawal
# on the cdk-payments stack so that a WITHDRAWAL-driven certificate settles on
# L1 with NO pessimistic-proof BalanceUnderflow.
#
# Why this exists (D1b-fix3): agglayer's pessimistic proof enforces value
# conservation — a network's local balance tree (LBT) only credits *claimed*
# imported bridge exits, never genesis `--alloc` balances. So to withdraw
# (L2->L1 bridgeAsset) native without underflowing the LBT, the native must
# first have entered via an L1->paychain deposit that is CLAIMED on paychain.
# This script does exactly that, then withdraws strictly less than it claimed.
#
# Steps:
#   1. Deposit  DEPOSIT_WEI of native L1 ETH -> paychain (L1 bridgeAsset).
#   2. Wait for the deposit to become provable, fetch its merkle proof from the
#      aggkit bridge REST (/bridge/v1/claim-proof), and CLAIM it on paychain
#      (L2 claimAsset). This credits the paychain LBT with DEPOSIT_WEI.
#   3. Wait until aggkit indexes the claim (/bridge/v1/claims?network_id=<l2>).
#   4. Withdraw WITHDRAW_WEI (<= DEPOSIT_WEI) native paychain -> L1
#      (L2 bridgeAsset, destination network 0).
#
# NOTE: In the intended flow the claim (step 2) is performed automatically by
# the aggkit/bridge-hub AUTOCLAIM service — you should not need to claim by
# hand. As of D1b-fix3 the external bridge-hub-autoclaim image mis-encodes the
# claimAsset call (viem AbiEncodingLengthMismatchError: "Expected length
# (params): 11, Given length (values): 32" — it flattens a bytes32[32] proof
# array into the top-level args) and also pre-flights an isClaimed() getter the
# paychain bridge facade does not implement, so no claim ever lands on paychain
# (/bridge/v1/claims?network_id=<l2> stays empty). This script performs the
# claim manually ONLY to unblock and exercise the deposit->claim->withdraw path
# end to end; fixing the autoclaim so claims happen automatically is tracked as
# a separate follow-up (paychain's claimAsset facade itself is correct — the
# bug is entirely on the autoclaim/caller side).
#
# cast/polycli run INSIDE an enclave toolbox container (host-mapped ports are
# not reliably reachable by cast); REST/eth_call use host curl via
# `kurtosis port print`.
#
# Env knobs:
#   ENCLAVE            kurtosis enclave name         (default: cdk-payments)
#   DEPOSIT_WEI        L1->L2 deposit amount         (default: 1000000000000000000 = 1 ETH)
#   WITHDRAW_WEI       L2->L1 withdraw amount        (default: 100000000000000000 = 0.1 ETH)
#   PRIVATE_KEY        tx signer (L1-funded)         (default: l2 admin key from input_args)
#   L1_BRIDGE_ADDRESS  override L1 bridge address    (default: resolved from combined.json)
#   L2_BRIDGE_ADDRESS  override paychain bridge addr (default: resolved from combined.json)
set -uo pipefail

ENCLAVE="${ENCLAVE:-cdk-payments}"
DEPOSIT_WEI="${DEPOSIT_WEI:-1000000000000000000}"
WITHDRAW_WEI="${WITHDRAW_WEI:-100000000000000000}"
CONTRACTS_SVC="contracts-001"
PAYCHAIN_SVC="paychain-node-001"
BRIDGE_SVC="aggkit-001-bridge"

# In-network service DNS (used by cast/polycli inside a toolbox container).
L1_IN="http://el-1-geth-lighthouse:8545"
L2_IN="http://${PAYCHAIN_SVC}:8545"

log()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; exit 1; }

command -v kurtosis >/dev/null || fail "kurtosis not on PATH"

# --- pick a toolbox container that has cast + polycli ---------------------
pick_tool_container() {
  local c
  for pat in 'l2-tx-spammer' 'l1-tx-spammer' 'bridge-spammer' 'test-runner' 'tx-spammer'; do
    c="$(docker ps --format '{{.Names}}' | grep -m1 -E "$pat" || true)"
    [[ -n "$c" ]] && { echo "$c"; return; }
  done
  # last resort: any container that has cast
  for c in $(docker ps --format '{{.Names}}'); do
    docker exec "$c" sh -c 'command -v cast && command -v polycli' >/dev/null 2>&1 && { echo "$c"; return; }
  done
}
TOOL_C="$(pick_tool_container)"
[[ -n "$TOOL_C" ]] || fail "no enclave toolbox container with cast/polycli found"
cexec() { docker exec "$TOOL_C" "$@"; }
log "using toolbox container: $TOOL_C"

# --- host-side REST base (curl) ------------------------------------------
BR_HOST="$(kurtosis port print "$ENCLAVE" "$BRIDGE_SVC" rest 2>/dev/null || true)"
[[ -n "$BR_HOST" && "$BR_HOST" != http* ]] && BR_HOST="http://$BR_HOST"
[[ -n "$BR_HOST" ]] || fail "could not resolve $BRIDGE_SVC rest port"

# --- resolve config from combined.json + input_args ----------------------
COMBINED="$(kurtosis service exec "$ENCLAVE" "$CONTRACTS_SVC" 'cat /opt/zkevm/combined.json' 2>/dev/null)"
addr_field() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"0x[0-9a-fA-F]{40}\"" | grep -oE '0x[0-9a-fA-F]{40}' | head -1; }
first_addr() { local k v; for k in "$@"; do v="$(echo "$COMBINED" | addr_field "$k")"; [[ -n "$v" ]] && { echo "$v"; return; }; done; }

L1_BRIDGE="${L1_BRIDGE_ADDRESS:-$(first_addr polygonZkEVMBridgeAddress bridgeAddress AgglayerBridge)}"
# The paychain bridge facade shares the sovereign bridge's deterministic
# CREATE2 address (same value as the L1 bridge). combined.json records it as
# polygonZkEVML2BridgeAddress; fall back to the L1 bridge value if absent.
L2_BRIDGE="${L2_BRIDGE_ADDRESS:-$(first_addr polygonZkEVML2BridgeAddress l2SovereignBridgeAddress AgglayerBridge)}"
[[ -z "$L2_BRIDGE" ]] && L2_BRIDGE="$L1_BRIDGE"
[[ -n "$L1_BRIDGE" ]] || fail "could not resolve L1 bridge address (set L1_BRIDGE_ADDRESS)"
[[ -n "$L2_BRIDGE" ]] || fail "could not resolve paychain bridge address (set L2_BRIDGE_ADDRESS)"

L1_CHAIN_ID="$(cexec cast chain-id --rpc-url "$L1_IN" 2>/dev/null || echo '')"
L2_CHAIN_ID="$(cexec cast chain-id --rpc-url "$L2_IN" 2>/dev/null || echo '')"
[[ -n "$L1_CHAIN_ID" && -n "$L2_CHAIN_ID" ]] || fail "could not read chain ids"

# l2 network id (rollup id) — read from combined.json or default to 1.
L2_NETWORK_ID="$(echo "$COMBINED" | grep -oE '"rollupID"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
[[ -z "$L2_NETWORK_ID" ]] && L2_NETWORK_ID=1

# signer key
PRIVATE_KEY="${PRIVATE_KEY:-0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
ETH_ADDR="$(cexec cast wallet address --private-key "$PRIVATE_KEY")"

echo "L1_BRIDGE=$L1_BRIDGE  L2_BRIDGE=$L2_BRIDGE"
echo "L1_CHAIN_ID=$L1_CHAIN_ID  L2_CHAIN_ID=$L2_CHAIN_ID  L2_NETWORK_ID=$L2_NETWORK_ID"
echo "signer=$ETH_ADDR  deposit=$DEPOSIT_WEI  withdraw=$WITHDRAW_WEI"
(( WITHDRAW_WEI <= DEPOSIT_WEI )) || fail "WITHDRAW_WEI must be <= DEPOSIT_WEI (PP value conservation)"

# --- 1. deposit L1 -> paychain -------------------------------------------
log "1/4 deposit ${DEPOSIT_WEI} wei L1 -> paychain (dest network ${L2_NETWORK_ID})"
cexec polycli ulxly bridge asset \
  --value "$DEPOSIT_WEI" --gas-limit 1250000 \
  --bridge-address "$L1_BRIDGE" --destination-address "$ETH_ADDR" \
  --destination-network "$L2_NETWORK_ID" \
  --rpc-url "$L1_IN" --private-key "$PRIVATE_KEY" --chain-id "$L1_CHAIN_ID" \
  --pretty-logs=false 2>&1 | grep -iE 'depositCount|txHash|transaction|error' | tail -6

# --- 2. wait for provable deposit, fetch proof, claim on paychain ---------
log "2/4 waiting for deposit to become provable, then claiming on paychain"
DEP_COUNT=""; LEAF_IDX=""
for _ in $(seq 1 60); do
  # newest L1->paychain native deposit for our address that is not yet claimed
  DEP_COUNT="$(curl -s -m 10 "$BR_HOST/bridge/v1/bridges?network_id=0" 2>/dev/null | python3 -c "
import sys,json
me='${ETH_ADDR}'.lower()
try: d=json.load(sys.stdin)
except: sys.exit(0)
cands=[b for b in d.get('bridges',[]) if b.get('destination_network')==${L2_NETWORK_ID} and b.get('destination_address','').lower()==me and str(b.get('amount'))=='${DEPOSIT_WEI}']
if cands: print(max(c['deposit_count'] for c in cands))
" 2>/dev/null)"
  if [[ -n "$DEP_COUNT" ]]; then
    LEAF_IDX="$(curl -s -m 10 "$BR_HOST/bridge/v1/l1-info-tree-index?network_id=0&deposit_count=${DEP_COUNT}" 2>/dev/null | grep -oE '^[0-9]+' || true)"
    [[ -n "$LEAF_IDX" ]] && break
  fi
  sleep 10
done
[[ -n "$DEP_COUNT" && -n "$LEAF_IDX" ]] || fail "deposit did not become provable in time (dep_count=$DEP_COUNT leaf_idx=$LEAF_IDX)"
echo "deposit_count=$DEP_COUNT  l1_info_tree_index=$LEAF_IDX"

# Claim with retry: claimAsset verifies the deposit's GER against the GERs the
# aggoracle has injected into paychain. A freshly-made deposit's covering GER
# may not be injected yet, so the first attempt can return status 0 (facade
# rejects an unknown GER). Re-fetch the proof and re-send until it succeeds
# (status 1) or aggkit indexes the claim.
log "claiming deposit ${DEP_COUNT} (amount ${DEPOSIT_WEI}) on paychain (retrying until GER is injected)"
claim_ok=""
for _ in $(seq 1 30); do
  # already indexed? (a prior attempt landed)
  n="$(curl -s -m 10 "$BR_HOST/bridge/v1/claims?network_id=${L2_NETWORK_ID}" 2>/dev/null | grep -oE '"count":[0-9]+' | grep -oE '[0-9]+' | head -1 || echo 0)"
  [[ "${n:-0}" -ge 1 ]] && { claim_ok="yes"; break; }

  ARGS_FILE="$(mktemp)"
  curl -s -m 15 "$BR_HOST/bridge/v1/claim-proof?network_id=0&leaf_index=${LEAF_IDX}&deposit_count=${DEP_COUNT}" 2>/dev/null \
    | DEP_COUNT="$DEP_COUNT" BR_HOST="$BR_HOST" L2NET="$L2_NETWORK_ID" python3 -c "
import sys,os,json,urllib.request
pr=json.load(sys.stdin)
dc=int(os.environ['DEP_COUNT']); br=os.environ['BR_HOST']; net=int(os.environ['L2NET'])
bs=json.load(urllib.request.urlopen(br+'/bridge/v1/bridges?network_id=0',timeout=10))['bridges']
dep=[b for b in bs if b['deposit_count']==dc and b['destination_network']==net][0]
leaf=pr['l1_info_tree_leaf']
print('['+','.join(pr['proof_local_exit_root'])+']')
print('['+','.join(pr['proof_rollup_exit_root'])+']')
print(dep['global_index'])
print(leaf['mainnet_exit_root']); print(leaf['rollup_exit_root'])
print(dep['origin_network']); print(dep['origin_address'])
print(dep['destination_network']); print(dep['destination_address'])
print(dep['amount']); print(dep.get('metadata') or '0x')
" > "$ARGS_FILE" 2>/dev/null
  if [[ "$(wc -l < "$ARGS_FILE")" -ge 11 ]]; then
    mapfile -t A < "$ARGS_FILE"
    status="$(cexec cast send "$L2_BRIDGE" \
      "claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)" \
      "${A[0]}" "${A[1]}" "${A[2]}" "${A[3]}" "${A[4]}" "${A[5]}" "${A[6]}" "${A[7]}" "${A[8]}" "${A[9]}" "${A[10]}" \
      --rpc-url "$L2_IN" --private-key "$PRIVATE_KEY" --chain-id "$L2_CHAIN_ID" \
      --legacy --gas-limit 3000000 2>&1 | grep -iE '^status' | head -1 || true)"
    echo "  claim attempt: ${status:-<no status>}"
    [[ "$status" == *"1 (success)"* ]] && { claim_ok="yes"; break; }
  fi
  rm -f "$ARGS_FILE"
  sleep 12
done
[[ -n "$claim_ok" ]] || fail "claim did not succeed (GER for the deposit never became claimable on paychain)"

# --- 3. wait until aggkit indexes the claim ------------------------------
log "3/4 waiting for aggkit to index the claim on paychain (network ${L2_NETWORK_ID})"
claimed=""
for _ in $(seq 1 30); do
  n="$(curl -s -m 10 "$BR_HOST/bridge/v1/claims?network_id=${L2_NETWORK_ID}" 2>/dev/null | grep -oE '"count":[0-9]+' | grep -oE '[0-9]+' || echo 0)"
  echo "  claims indexed: ${n:-0}"
  [[ "${n:-0}" -ge 1 ]] && { claimed="yes"; break; }
  sleep 6
done
[[ -n "$claimed" ]] || fail "claim was not indexed by aggkit in time"

# --- 4. withdraw (<=deposit) paychain -> L1 ------------------------------
log "4/4 withdrawing ${WITHDRAW_WEI} wei paychain -> L1 (bridgeAsset, dest network 0)"
cexec polycli ulxly bridge asset \
  --value "$WITHDRAW_WEI" --gas-limit 1250000 \
  --bridge-address "$L2_BRIDGE" --destination-address "$ETH_ADDR" \
  --destination-network 0 \
  --rpc-url "$L2_IN" --private-key "$PRIVATE_KEY" --chain-id "$L2_CHAIN_ID" \
  --pretty-logs=false 2>&1 | grep -iE 'depositCount|txHash|transaction|error' | tail -6

log "DONE — deposit->claim->withdraw submitted. The withdrawal is a local exit"
echo "backed by the claimed imported bridge exit; its certificate should settle"
echo "with NO BalanceUnderflow. Watch AggchainPayments.PaymentsStateUpdated and"
echo "agglayer logs (should show NO 'BalanceUnderflow')."
