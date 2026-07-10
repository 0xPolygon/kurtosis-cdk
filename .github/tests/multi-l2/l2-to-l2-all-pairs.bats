#!/usr/bin/env bats
# bats file_tags=aggkit
# shellcheck disable=SC2154,SC2034
#
# Full-mesh L2<->L2 bridge coverage for the multi-l2 job.
#
# For EVERY ordered pair of attached L2 rollups (src != dst) this bridges a
# message src -> dst and claims it on dst, so with num_chains=3 all six ordered
# pairs are exercised (1->2, 2->1, 1->3, 3->1, 2->3, 3->2) and with num_chains=2
# both directions of the single pair (1->2, 2->1).
#
# It lives in kurtosis-cdk (not the agglayer/e2e checkout) and is run against the
# checked-out agglayer/e2e helpers via an absolute load path, exactly like the
# workflow runs the repo's other agglayer/e2e bats. It reuses the same helpers as
# tests/aggkit/bridge-e2e-2-chains.bats ("Transfer message L2 to L2"): message
# bridging + process_bridge_claim-style injected-leaf polling, so it needs NO
# host-built aggsender-find-imported-bridge binary (unlike the asset case's
# wait_to_settle_certificate_containing_global_index).
#
# NUM_CHAINS (env, default 2) selects how many rollups participate.

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
    # rollups are already registered with agglayer at deploy time, and for the
    # pessimistic/ecdsa-multisig and FEP consensus we run, the aggsender pushes
    # certificates to agglayer over gRPC — agglayer needs no [full-node-rpcs] entry
    # to settle them (confirmed: certs settle and every L2<->L2 claim below succeeds
    # without it). The e2e helper only patches the LEGACY config path
    # (/etc/zkevm/agglayer-config.toml, not the image's /etc/agglayer/config.toml),
    # and whenever its idempotency grep does not short-circuit it runs
    # `kurtosis service stop/start agglayer` — a needless restart on the settlement
    # critical path that intermittently fails ("container name already in use") and
    # aborts setup. Since the registration is a genuine no-op for us, we skip the
    # call entirely rather than paper over it with a seeded stub file.
}

# Claim an L2->L2 bridge on the destination rollup. Mirrors process_bridge_claim
# but with larger retry budgets: a claim only becomes ready once the SOURCE
# rollup's certificate carrying the exit settles on L1 (and the destination's
# aggoracle injects the resulting GER). For the op-succinct/FEP rollup that
# settlement is slow (~25 min on a contended CI runner), which exceeds
# process_bridge_claim's fixed 50x25s (~20 min) per-step caps.
#   $1 ctx  $2 origin_net  $3 tx_hash  $4 dst_net  $5 bridge_addr
#   $6 origin_bridge_url  $7 dst_bridge_url  $8 dst_rpc_url
_claim_l2_to_l2() {
    local ctx="$1" origin_net="$2" tx="$3" dst_net="$4" bridge_addr="$5"
    local origin_url="$6" dst_url="$7" dst_rpc="$8"
    local max_attempts=90 poll=20  # up to ~30 min per step, covers slow FEP settlement
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

@test "Bridge message across every L2<->L2 rollup pair" {
    local chains=(1 2)
    [[ "${NUM_CHAINS:-2}" -eq 3 ]] && chains=(1 2 3)

    # Message-only bridge: native token, zero value, fixed metadata we assert on
    # the destination claim.
    amount=0
    meta_bytes="0xbeef"
    destination_addr=$sender_addr

    # Phase 1 — bridge on every ordered pair FIRST, so the per-source certificate
    # settlement waits (the slow part for FEP) overlap instead of running serially.
    local -a pair_src=() pair_dst=() pair_tx=()
    local src dst
    for src in "${chains[@]}"; do
        for dst in "${chains[@]}"; do
            [[ "$src" == "$dst" ]] && continue
            local src_rpc_var="l2_rpc_url_${src}" dst_net_var="rollup_${dst}_network_id"
            destination_net="${!dst_net_var}"
            echo "=== [bridge] L2(Rollup ${src}) -> L2(Rollup ${dst}) net=${destination_net}" >&3
            run bridge_message "$native_token_addr" "${!src_rpc_var}" "$l2_bridge_addr"
            assert_success
            pair_src+=("$src"); pair_dst+=("$dst"); pair_tx+=("$output")
        done
    done

    # Phase 2 — claim each bridge on its destination and verify the message payload.
    local i
    for i in "${!pair_src[@]}"; do
        src="${pair_src[$i]}"; dst="${pair_dst[$i]}"
        local tx="${pair_tx[$i]}"
        local src_net_var="rollup_${src}_network_id" dst_net_var="rollup_${dst}_network_id"
        local src_url_var="aggkit_bridge_${src}_url" dst_url_var="aggkit_bridge_${dst}_url"
        local dst_rpc_var="l2_rpc_url_${dst}"

        echo "=== [claim] L2(Rollup ${src}) -> L2(Rollup ${dst}) tx=${tx}" >&3
        run _claim_l2_to_l2 "all-pairs ${src}->${dst}" \
            "${!src_net_var}" "$tx" "${!dst_net_var}" "$l2_bridge_addr" \
            "${!src_url_var}" "${!dst_url_var}" "${!dst_rpc_var}"
        assert_success
        local claim_global_index="$output"

        run get_claim "${!dst_net_var}" "$claim_global_index" 50 10 "${!dst_url_var}"
        assert_success
        assert_equal "$(echo "$output" | jq -r '.metadata')" "$meta_bytes"
        echo "=== [ok] L2(Rollup ${src}) -> L2(Rollup ${dst}) global_index=${claim_global_index}" >&3
    done
}
