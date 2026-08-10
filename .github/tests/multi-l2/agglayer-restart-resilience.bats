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
#   1. record S's baseline settled AND known (communicated) certificate heights,
#   2. bridge a message S -> D (starts cert generation for a fresh exit),
#   3. stop the `agglayer` service (the outage begins),
#   4. issue a burst of further bridges WHILE agglayer is down (their exits are
#      created during the outage, so their cert generation/communication overlaps it),
#   4b. hold the outage open until we CATCH the aggsender failing to COMMUNICATE a
#      certificate to the down agglayer (proof the downtime overlapped the certificate-
#      communication phase, not just idle time),
#   5. explicitly assert settlement is impossible while agglayer is down (service
#      STOPPED + settlement RPC unreachable),
#   6. restart agglayer (stop-then-start to dodge the container-name flake) and wait
#      until its read-rpc answers again,
#   7-8. (CLAIM mode) claim EVERY bridge (pre-outage + burst) on D asserting the 0xbeef
#      payload, and assert S's settled certificate height advanced past the baseline, and
#   9. assert S's known certificate height advanced past baseline — since agglayer could
#      not receive anything while down, this proves the certificate-communication path
#      itself recovered (the aggsender re-communicated after the restart).
#
# Two @tests exercise this:
#   - PP source (rollup-1 -> rollup-2) in CLAIM mode: the full end-to-end flow above.
#   - FEP source (rollup-3) in COMM mode (num_chains=3 only): steps 1-6 + 9 ONLY. It
#     skips the cross-network claim + settlement assertion (steps 7-8) because the FEP
#     source's deposit-count lookup is slow and flaky under runner contention, and FEP
#     end-to-end claimability/settlement is already covered by the healthy "all pairs"
#     step. The known-height advance (step 9) is the reliable communication-recovery
#     signal, and the aggsender<->agglayer communication path is identical for PP and FEP.
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

# Latest KNOWN certificate height for a network id — the height of the most recent certificate
# the aggsender has COMMUNICATED to agglayer (received but not necessarily settled yet). Used to
# prove the certificate-communication path recovered after the outage, distinct from settlement.
_known_height() {
    local nid="$1" readrpc="$2"
    cast rpc --rpc-url "$readrpc" interop_getLatestKnownCertificateHeader "$nid" 2>/dev/null \
        | jq -r '.height // empty' 2>/dev/null || true
}

# Scan the source rollup's aggsender (aggkit-00X) log for evidence that a certificate
# COMMUNICATION to the (currently down) agglayer failed — i.e. the outage overlapped the
# certificate-communication phase, not just idle downtime. Echoes the matching line(s) (empty
# if none matched). Best-effort: the wording is aggkit-version-sensitive, so callers must treat
# an empty result as "not observed", not as a failure.
_aggsender_comm_failure() {
    local src="$1" svc
    svc="$(printf 'aggkit-%03d' "$src")"
    kurtosis service logs "$ENCLAVE_NAME" "$svc" --num 400 2>/dev/null \
        | grep -Ei 'certificate|agglayer|aggsender' \
        | grep -Ei 'connection refused|transport|unavailable|dial tcp|failed to send|error sending|cannot send|send.*fail|rpc error' \
        | tail -n 3 || true
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

# $1 src rollup index   $2 dst rollup index   $3 mode
#   mode "claim" (default) — full end-to-end recovery: after the outage, CLAIM every bridge on the
#                            destination and assert both settled and known cert heights advanced.
#                            Used for the fast PP source (1->2).
#   mode "comm"            — cheap communication-recovery check: after the outage, assert only that
#                            the source rollup's KNOWN cert height advanced (the aggsender re-
#                            communicated with agglayer). Skips the cross-network claim, whose
#                            deposit-count lookup is slow and flaky under runner contention for the
#                            FEP source. Used for the FEP source (3), whose end-to-end claimability
#                            is already covered by the "all pairs" step's healthy 3->* claims.
_run_resilience_case() {
    local src="$1" dst="$2" mode="${3:-claim}"
    local src_rpc_var="l2_rpc_url_${src}" dst_rpc_var="l2_rpc_url_${dst}"
    local src_net_var="rollup_${src}_network_id" dst_net_var="rollup_${dst}_network_id"
    local src_url_var="aggkit_bridge_${src}_url" dst_url_var="aggkit_bridge_${dst}_url"
    local src_rpc="${!src_rpc_var}" dst_rpc="${!dst_rpc_var}"
    local src_net="${!src_net_var}" dst_net="${!dst_net_var}"
    local src_url="${!src_url_var}" dst_url="${!dst_url_var}"

    # The aggsender's failure to reach a DOWN agglayer surfaces as a gRPC dial timeout ~30-40s
    # into an outage, so the window must comfortably exceed that to catch the communication
    # failure (step 4b). 60s gives margin; PP settlement after restart is still fast.
    local downtime="${AGGLAYER_DOWNTIME_SEC:-60}"
    local burst="${AGGLAYER_OUTAGE_BRIDGES:-3}"

    # Known-height recovery budget (step 9). PP (claim mode) advances known immediately via the
    # claims, so a short wait suffices. FEP (comm mode) re-communicates on its own proof-gated
    # cadence after the restart — slow and resource-bound on a contended runner: the op-succinct
    # proposer must aggregate past the deposit's block, gated on L1 finalization + a live GER — so
    # give it a large budget and a coarser poll. In CI this budget is set (AGGLAYER_KNOWN_TIMEOUT_MIN)
    # to EXCEED the job's timeout-minutes, so a genuinely-slow FEP source waits for the job timeout
    # instead of erroring out early; the poll still exits the instant known height advances.
    local known_poll=10 known_timeout_min=2
    if [[ "$mode" == "comm" ]]; then
        known_timeout_min="${AGGLAYER_KNOWN_TIMEOUT_MIN:-30}"
        known_poll="${AGGLAYER_KNOWN_POLL:-30}"
    fi
    local known_max=$(( known_timeout_min * 60 / known_poll ))
    # bridge_message reads these from the caller's scope (dynamic scoping), exactly like
    # l2-to-l2-all-pairs.bats sets them before each call: a native zero-value message with a
    # fixed metadata we assert on the destination claim, addressed to the destination network.
    local meta_bytes="0xbeef"
    local destination_addr="$sender_addr"
    local destination_net="$dst_net"
    local amount=0

    # 1. Baseline: source rollup's current settled AND known (communicated) cert heights (-1
    #    if none yet). We assert both advance after the outage: settled proves settlement
    #    recovered, known proves the certificate-COMMUNICATION path recovered.
    local readrpc h0 k0
    readrpc="$(_agglayer_readrpc)"
    h0="$(_settled_height "$src_net" "$readrpc")"
    [[ -z "$h0" ]] && h0=-1
    k0="$(_known_height "$src_net" "$readrpc")"
    [[ -z "$k0" ]] && k0=-1
    echo "=== [baseline] rollup ${src} net=${src_net} settled height=${h0} known height=${k0}" >&3

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

    # 4. Bridge burst right after the outage starts (a few seconds apart) so several exits are
    #    created WHILE agglayer is down; their certificates can only be communicated/settled
    #    after the restart. Bridge txs land on L2 fine — the L2 RPC is independent of agglayer.
    local i
    for (( i = 1; i <= burst; i++ )); do
        run bridge_message "$native_token_addr" "$src_rpc" "$l2_bridge_addr"
        assert_success
        txs+=("$output")
        echo "=== [bridge during-outage ${i}/${burst}] L2(${src})->L2(${dst}) tx=${output}" >&3
        sleep 3
    done

    # 4b. Hold the outage open until we CATCH the aggsender failing to COMMUNICATE with the down
    #     agglayer — proof the downtime overlapped the certificate-communication phase, not just
    #     idle time. The aggsender's gRPC dial to agglayer times out ~30-40s into an outage, so
    #     poll its log every 5s (up to the downtime window) for that transport/Unavailable
    #     failure and break as soon as we see one. Best-effort: the wording is aggkit-version-
    #     sensitive, so absence does not fail the test — the deterministic proof is the known +
    #     settled height advance after recovery (steps 8-9).
    local comm_evidence="" held=0
    while (( held < downtime )); do
        comm_evidence="$(_aggsender_comm_failure "$src")"
        [[ -n "$comm_evidence" ]] && break
        sleep 5; held=$(( held + 5 ))
    done

    # 5. Explicitly assert settlement/communication is impossible while agglayer is down.
    run _agglayer_stopped
    assert_success
    # The read-rpc endpoint captured while up now refuses connections (an aggsender push
    # over gRPC fails the same way): a settlement query MUST error while agglayer is stopped.
    run cast rpc --rpc-url "$readrpc" interop_getLatestSettledCertificateHeader "$src_net"
    assert_failure
    echo "=== [outage] confirmed agglayer down: settlement RPC unreachable" >&3
    if [[ -n "$comm_evidence" ]]; then
        echo "=== [outage] caught aggsender FAILING TO COMMUNICATE a cert to the down agglayer:" >&3
        echo "$comm_evidence" >&3
    else
        echo "=== [outage] no explicit aggsender comm-failure line matched (version-sensitive); relying on the known/settled height-advance assertions after recovery" >&3
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

    # 7-8. End-to-end recovery (CLAIM mode only): EVERY bridge issued around the outage must be
    #      claimable on D, and a new certificate must have SETTLED. In COMM mode we skip both — the
    #      cross-network claim's deposit-count lookup is slow and flaky under runner contention for
    #      the FEP source, and FEP end-to-end claimability + settlement are already covered by the
    #      healthy "all pairs" step; comm mode instead proves communication recovery via the
    #      known-height assertion (step 9).
    local read_try
    if [[ "$mode" == "claim" ]]; then
        # 7. EVERY bridge issued around the outage must be claimable on D.
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
        #    The claims above already proved settlement happened, so retry a few times to ride
        #    out a transient read-rpc hiccup rather than flake on it.
        local h2=""
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
    else
        # comm mode: do not assert (slow) FEP settlement; just log it for context.
        local h2info; h2info="$(_settled_height "$src_net" "$readrpc")"
        echo "=== [recovery/comm] rollup ${src} settled height=${h2info:-none} (baseline=${h0}); FEP settlement is slow and covered by the all-pairs step, so it is NOT asserted here — communication recovery is asserted via known height below" >&3
    fi

    # 9. The certificate-COMMUNICATION path recovered: the source rollup's known certificate
    #    height (what agglayer has received from the aggsender) must have advanced past baseline.
    #    Since agglayer could not receive anything while it was down, a higher known height proves
    #    the aggsender successfully re-communicated a certificate after the restart. This is the
    #    core resilience signal, and the ONLY hard recovery assertion in comm mode (see steps 7-8).
    #    Poll up to the mode-based budget: PP exits on the first read (known already advanced via
    #    the claims), FEP waits for its next communicated cert.
    local k2=""
    for (( read_try = 1; read_try <= known_max; read_try++ )); do
        k2="$(_known_height "$src_net" "$readrpc")"
        [[ -n "$k2" && "$k2" -gt "$k0" ]] && break
        sleep "$known_poll"
    done
    [[ -z "$k2" ]] && k2=-1
    echo "=== [recovery] rollup ${src} known height after restart=${k2} (baseline=${k0})" >&3
    if (( k2 <= k0 )); then
        fail "known certificate height did not advance across the outage — certificate communication did not recover (baseline=${k0}, after=${k2})"
    fi
}

@test "agglayer restart during bridging - PP source (rollup-1 -> rollup-2), full claim" {
    _run_resilience_case 1 2 claim
}

# FEP source: communication-recovery check only. The full cross-network claim's deposit-count
# lookup is slow and flaky under runner contention for the FEP source, and FEP end-to-end
# claimability is already covered by the healthy "all pairs" step; here we only assert the FEP
# aggsender re-communicated with agglayer (known cert height advances) after the restart.
@test "agglayer restart during bridging - FEP source (rollup-3), communication recovery" {
    [[ "${NUM_CHAINS:-2}" -eq 3 ]] || skip "FEP resilience case requires num_chains=3"
    _run_resilience_case 3 1 comm
}
