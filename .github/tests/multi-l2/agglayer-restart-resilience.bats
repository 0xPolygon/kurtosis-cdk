#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034
#
# Agglayer restart resilience for the multi-l2 job.
#
# This proves that shutting the singleton `agglayer` node service down DURING the
# certificate generation/communication phase of live bridging — and restarting it —
# does not break certificate generation/settlement or the end-to-end bridge flow.
#
# For a source rollup S we:
#   1. record S's baseline settled certificate height,
#   2. bridge a message S -> D (starts cert generation for a fresh exit),
#   3. stop the `agglayer` service (the outage begins),
#   4. issue a burst of further bridges WHILE agglayer is down (their exits are
#      created during the outage, so their cert generation/communication overlaps it),
#   5. explicitly assert settlement is impossible while agglayer is down (service
#      STOPPED + settlement RPC unreachable),
#   6. restart agglayer (stop-then-start to dodge the container-name flake) and wait
#      until its read-rpc answers again,
#   7. claim EVERY bridge (pre-outage + burst) on D and assert the 0xbeef payload, and
#   8. assert S's settled certificate height advanced past the baseline (a new cert
#      settled after the restart, covering the exits created during the outage).
#
# It is intentionally self-contained (does NOT modify the CI-fragile
# l2-to-l2-all-pairs.bats): the setup() and _claim_l2_to_l2 helper below are copied
# from that file and MUST be kept in sync with it.
#
# NUM_CHAINS (env, default 2) selects how many rollups are attached; the FEP-source
# case is skipped unless num_chains=3.

setup() {
    load "${PROJECT_ROOT:?PROJECT_ROOT must point at the agglayer/e2e checkout}/core/helpers/agglayer-cdk-common-setup"

    # _agglayer_cdk_common_setup -> _load_helper_scripts sources its scripts with bats
    # `load` using paths RELATIVE to the running test file's directory ($BATS_TEST_DIRNAME):
    # `load "../../core/helpers/scripts/$script"`. That only resolves for tests living under
    # the e2e repo's tests/ tree. This test lives in kurtosis-cdk, so point BATS_TEST_DIRNAME
    # at the e2e tests dir for the duration of setup so those relative loads resolve against
    # the e2e checkout, then restore it.
    local _saved_bats_test_dirname="$BATS_TEST_DIRNAME"
    BATS_TEST_DIRNAME="${PROJECT_ROOT}/tests/aggkit"
    _agglayer_cdk_common_setup
    BATS_TEST_DIRNAME="$_saved_bats_test_dirname"

    _agglayer_cdk_common_multi_setup "${NUM_CHAINS:-2}"

    # NOTE: we deliberately do NOT call add_network_to_agglayer here. The attached
    # rollups are already registered with agglayer at deploy time, and the helper would
    # otherwise `kurtosis service stop/start agglayer` on the settlement critical path —
    # a restart this test performs deliberately and in a controlled way instead. See the
    # detailed note in l2-to-l2-all-pairs.bats setup().
}

teardown() {
    # Never leave the enclave with agglayer down: the post-run action flags STOPPED
    # services and a stopped agglayer would wedge later work. `start` on an already-running
    # service is a harmless no-op, so this is safe on both the pass and the failure path.
    kurtosis service start "${ENCLAVE_NAME:?}" agglayer >/dev/null 2>&1 || true
}

# --- Local helpers -----------------------------------------------------------------

# Read-rpc endpoint of the agglayer node. MUST be re-fetched after a restart because
# Kurtosis may remap the published host port.
_agglayer_readrpc() {
    kurtosis port print "$ENCLAVE_NAME" agglayer aglr-readrpc 2>/dev/null
}

# Latest SETTLED certificate height for a network id (empty if none / rpc unavailable).
_settled_height() {
    local nid="$1" readrpc="$2"
    cast rpc --rpc-url "$readrpc" interop_getLatestSettledCertificateHeader "$nid" 2>/dev/null \
        | jq -r '.height // empty' 2>/dev/null || true
}

# True (exit 0) only when the enclave lists the service named EXACTLY "agglayer" as STOPPED.
# Mirrors the STOPPED-detection in .github/actions/kurtosis-post-run (grep STOPPED then $2=Name).
# Matching the Name column exactly avoids the "agglayer-dashboard" substring collision.
_agglayer_stopped() {
    kurtosis enclave inspect "$ENCLAVE_NAME" 2>/dev/null \
        | grep -E '\bSTOPPED\b' \
        | awk '$2 == "agglayer" { found = 1 } END { exit(found ? 0 : 1) }'
}

# Claim an L2->L2 bridge on the destination rollup. Copied from l2-to-l2-all-pairs.bats —
# KEEP IN SYNC. Polls with a per-step wall-clock budget (L2L2_CLAIM_TIMEOUT_MIN minutes,
# every L2L2_CLAIM_POLL seconds); fast PP-source pairs exit early, so a generous budget only
# extends the wait for the slow FEP-source case.
#   $1 ctx  $2 origin_net  $3 tx_hash  $4 dst_net  $5 bridge_addr
#   $6 origin_bridge_url  $7 dst_bridge_url  $8 dst_rpc_url
_claim_l2_to_l2() {
    local ctx="$1" origin_net="$2" tx="$3" dst_net="$4" bridge_addr="$5"
    local origin_url="$6" dst_url="$7" dst_rpc="$8"
    local poll="${L2L2_CLAIM_POLL:-20}"
    local timeout_min="${L2L2_CLAIM_TIMEOUT_MIN:-30}"
    local max_attempts=$(( timeout_min * 60 / poll ))
    local bridge deposit_count l1_info_tree_index injected proof global_index

    bridge="$(get_bridge "$ctx" "$origin_net" "$tx" "$max_attempts" "$poll" "$origin_url")" || return 1
    deposit_count="$(echo "$bridge" | jq -r '.deposit_count')"
    l1_info_tree_index="$(find_l1_info_tree_index_for_bridge "$origin_net" "$deposit_count" "$max_attempts" "$poll" "$origin_url" "$ctx")" || return 1
    injected="$(find_injected_l1_info_leaf "$dst_net" "$l1_info_tree_index" "$max_attempts" "$poll" "$dst_url")" || return 1
    l1_info_tree_index="$(echo "$injected" | jq -r '.l1_info_tree_index')"
    proof="$(generate_claim_proof "$origin_net" "$deposit_count" "$l1_info_tree_index" "$max_attempts" "$poll" "$origin_url")" || return 1
    global_index="$(claim_bridge "$bridge" "$proof" "$dst_rpc" "$max_attempts" "$poll" "$bridge_addr")" || return 1
    echo "$global_index"
}

# --- Parameterized resilience flow -------------------------------------------------

# $1 src rollup index   $2 dst rollup index
_run_resilience_case() {
    local src="$1" dst="$2"
    local src_rpc_var="l2_rpc_url_${src}" dst_rpc_var="l2_rpc_url_${dst}"
    local src_net_var="rollup_${src}_network_id" dst_net_var="rollup_${dst}_network_id"
    local src_url_var="aggkit_bridge_${src}_url" dst_url_var="aggkit_bridge_${dst}_url"
    local src_rpc="${!src_rpc_var}" dst_rpc="${!dst_rpc_var}"
    local src_net="${!src_net_var}" dst_net="${!dst_net_var}"
    local src_url="${!src_url_var}" dst_url="${!dst_url_var}"

    local downtime="${AGGLAYER_DOWNTIME_SEC:-45}"
    local burst="${AGGLAYER_OUTAGE_BRIDGES:-3}"
    # bridge_message reads these from the caller's scope (dynamic scoping), exactly like
    # l2-to-l2-all-pairs.bats sets them before each call: a native zero-value message with a
    # fixed metadata we assert on the destination claim, addressed to the destination network.
    local meta_bytes="0xbeef"
    local destination_addr="$sender_addr"
    local destination_net="$dst_net"
    local amount=0

    # 1. Baseline: source rollup's current settled certificate height (-1 if none yet).
    local readrpc h0
    readrpc="$(_agglayer_readrpc)"
    h0="$(_settled_height "$src_net" "$readrpc")"
    [[ -z "$h0" ]] && h0=-1
    echo "=== [baseline] rollup ${src} net=${src_net} settled height=${h0}" >&3

    # 2. Pre-outage bridge — starts certificate generation for a fresh exit.
    local -a txs=()
    run bridge_message "$native_token_addr" "$src_rpc" "$l2_bridge_addr"
    assert_success
    txs+=("$output")
    echo "=== [bridge pre-outage] L2(${src})->L2(${dst}) tx=${output}" >&3

    # 3. Start the outage.
    echo "=== [outage] stopping agglayer" >&3
    run kurtosis service stop "$ENCLAVE_NAME" agglayer
    assert_success
    run _agglayer_stopped
    assert_success

    # 4. Bridge burst DURING the outage, spread across the downtime window, so these
    #    exits' cert generation/communication is guaranteed to overlap the outage. Bridge
    #    txs land on L2 fine — the L2 RPC is independent of agglayer.
    local interval=$(( downtime / (burst + 1) ))
    (( interval < 1 )) && interval=1
    local i
    for (( i = 1; i <= burst; i++ )); do
        sleep "$interval"
        run bridge_message "$native_token_addr" "$src_rpc" "$l2_bridge_addr"
        assert_success
        txs+=("$output")
        echo "=== [bridge during-outage ${i}/${burst}] L2(${src})->L2(${dst}) tx=${output}" >&3
    done
    # Pad out the remainder so the outage clearly spans a full generation/communication cycle.
    sleep "$interval"

    # 5. Explicitly assert settlement/communication is impossible while agglayer is down.
    run _agglayer_stopped
    assert_success
    # The read-rpc endpoint captured while up now refuses connections (an aggsender push
    # over gRPC fails the same way): a settlement query MUST error while agglayer is stopped.
    run cast rpc --rpc-url "$readrpc" interop_getLatestSettledCertificateHeader "$src_net"
    assert_failure
    echo "=== [outage] confirmed agglayer down: settlement RPC unreachable" >&3
    # Best-effort corroboration from the source aggsender's own logs (non-fatal — log
    # wording is version-sensitive; the two assertions above are the hard proof).
    local aggkit_svc err_lines
    aggkit_svc="$(printf 'aggkit-%03d' "$src")"
    err_lines="$(kurtosis service logs "$ENCLAVE_NAME" "$aggkit_svc" 2>/dev/null \
        | grep -Ei 'connection refused|transport|unavailable|dial tcp|failed to send|error sending certificate' \
        | tail -n 5 || true)"
    if [[ -n "$err_lines" ]]; then
        echo "=== [outage] ${aggkit_svc} push/connection errors during downtime:" >&3
        echo "$err_lines" >&3
    fi

    # 6. Restart agglayer (stop-then-start dodges the "container name already in use" flake)
    #    and wait until its read-rpc answers again.
    echo "=== [recovery] restarting agglayer" >&3
    kurtosis service stop "$ENCLAVE_NAME" agglayer || true
    run kurtosis service start "$ENCLAVE_NAME" agglayer
    assert_success
    local up="" attempt
    for attempt in $(seq 1 60); do
        readrpc="$(_agglayer_readrpc || true)"
        if [[ -n "$readrpc" ]] \
            && cast rpc --rpc-url "$readrpc" interop_getLatestSettledCertificateHeader "$src_net" >/dev/null 2>&1; then
            up=1
            break
        fi
        sleep 5
    done
    if [[ -z "$up" ]]; then
        fail "agglayer did not recover: read-rpc never answered after restart"
    fi
    echo "=== [recovery] agglayer healthy again (readrpc=${readrpc})" >&3

    # 7. End-to-end recovery: EVERY bridge issued around the outage must be claimable on D.
    local tx global_index
    for tx in "${txs[@]}"; do
        echo "=== [claim] L2(${src})->L2(${dst}) tx=${tx}" >&3
        run _claim_l2_to_l2 "resilience ${src}->${dst}" \
            "$src_net" "$tx" "$dst_net" "$l2_bridge_addr" \
            "$src_url" "$dst_url" "$dst_rpc"
        assert_success
        global_index="$output"

        run get_claim "$dst_net" "$global_index" 50 10 "$dst_url"
        assert_success
        assert_equal "$(echo "$output" | jq -r '.metadata')" "$meta_bytes"
        echo "=== [ok] L2(${src})->L2(${dst}) global_index=${global_index}" >&3
    done

    # 8. A new certificate settled after the restart (covering exits created during the
    #    outage): the source rollup's settled height must have advanced past the baseline.
    #    The step-7 claims already proved settlement happened, so retry a few times to ride
    #    out a transient read-rpc hiccup rather than flake on it.
    local h2="" read_try
    for read_try in $(seq 1 5); do
        h2="$(_settled_height "$src_net" "$readrpc")"
        [[ -n "$h2" ]] && break
        sleep 3
    done
    [[ -z "$h2" ]] && h2=-1
    echo "=== [recovery] rollup ${src} settled height after restart=${h2} (baseline=${h0})" >&3
    if (( h2 <= h0 )); then
        fail "settled certificate height did not advance across the outage (baseline=${h0}, after=${h2})"
    fi
}

@test "agglayer restart during bridging - PP source (rollup-1 -> rollup-2)" {
    _run_resilience_case 1 2
}

@test "agglayer restart during bridging - FEP source (rollup-3 -> rollup-1)" {
    [[ "${NUM_CHAINS:-2}" -eq 3 ]] || skip "FEP resilience case requires num_chains=3"
    _run_resilience_case 3 1
}
