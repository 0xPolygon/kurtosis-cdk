#!/usr/bin/env bash
#
# Anvil-aggkit flavor verification (S9).
#
# This library is SOURCED by snapshot/verify.sh once it detects (via
# summary.json's "flavor" key) that the snapshot directory it was pointed at
# is an anvil-aggkit bundle, not the default geth/lighthouse one. It reuses
# the parent script's log()/log_error()/log_warn()/log_info()/log_step()/
# pass()/fail() helpers (already defined by the time verify.sh sources this
# file) but keeps its OWN test counters, so calling run_anvil_aggkit_verification
# has no effect whatsoever on the default flavor's TESTS_* globals if verify.sh
# is ever refactored to define them earlier.
#
# Every check here exercises the dev-ui contract table in the plan (§1):
# block progression + finalized on all three chains, bridge/GER bytecode,
# sync-status (both is_synced AND is_active, both sides), the tracker health
# endpoint, haproxy CORS preflight on every route, dev-ui /config.json, the
# the S9b historical-state invariant (aggkit config baked verbatim + the
# restored L1 answering state reads at pre-snapshot heights), and
# a full scripted bridge round trip (L1->L2 autoclaimed, L2->L1 parked at
# "ready to claim" and then manually claimed via cast).
#
# Hard-won context baked in (see plan S1/S4b/S6/S8 outcomes -- do not
# rediscover):
#   - The host `cast`/`forge` wrappers cannot reach kurtosis/compose-published
#     ports (no --network host). Every cast invocation below goes through a
#     throwaway `docker run --rm --network host ... foundry:latest` container.
#   - claimAsset's `originNetwork` is the ASSET's origin network (0 for
#     native ETH), never the network_id of the chain the deposit was
#     submitted on (F1, S6). Passing the source network_id reverts
#     InvalidSmtProof. This script reads origin_network from the `bridges`
#     REST listing for the exact deposit being claimed -- never guesses it.
#   - claim-proof's `leaf_index` is the L1-info-tree index, NOT the deposit
#     count (S4b). Get it from GET /bridge/v1/l1-info-tree-index first.
#   - The tracker's terminal state is tracking_status:"finished" with final
#     step_name:"Claimed" -- there is no "Completed" value.
#   - Transient tracker step errors (error_type_string:"transient") are
#     NORMAL mid-flight (retry_count reached ~14 in S6) and self-resolve;
#     never fail on the first one. A CertificatePending step whose *result*
#     carries status_string:"InError" is a DIFFERENT, non-transient signal
#     (the underlying agglayer certificate itself failed) -- if it persists
#     across several polls without change, that is treated as a genuine
#     failure, not something to keep waiting on.

# Idempotent source guard.
if [ -n "${_SNAPSHOT_LIB_VERIFY_ANVIL_AGGKIT_SOURCED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_SNAPSHOT_LIB_VERIFY_ANVIL_AGGKIT_SOURCED=1

# ============================================================================
# cast wrapper -- host foundry is unusable here (broken GLIBC on the host
# `cast`, and the host wrapper script lacks --network host so it cannot reach
# published ports even where it does run). Every call goes through a
# throwaway container instead, exactly as documented in
# plans/dev-ui-ci-snapshot/s4b-evidence/21-manual-claim-recipe.txt.
# ============================================================================
_verify_cast() {
    docker run --rm --network host --entrypoint=/usr/local/bin/cast \
        ghcr.io/foundry-rs/foundry:latest "$@"
}

# ============================================================================
# Test bookkeeping (deliberately separate from verify.sh's default-flavor
# TESTS_* globals -- see module doc above).
# ============================================================================
ANVIL_TESTS_PASSED=0
ANVIL_TESTS_FAILED=0
ANVIL_TESTS_TOTAL=0

anvil_test_result() {
    local test_name="$1" result="$2"
    ANVIL_TESTS_TOTAL=$((ANVIL_TESTS_TOTAL + 1))
    if [ "$result" = "pass" ]; then
        pass "$test_name"
        ANVIL_TESTS_PASSED=$((ANVIL_TESTS_PASSED + 1))
    else
        fail "$test_name"
        ANVIL_TESTS_FAILED=$((ANVIL_TESTS_FAILED + 1))
    fi
}

# rpc_call <url> <method> [params_json]
# Echoes the raw JSON-RPC response body.
rpc_call() {
    local url="$1" method="$2" params="${3:-[]}"
    curl -s -m 15 "$url" -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}"
}

# rpc_result <url> <method> [params_json]
# Echoes just .result (raw, not jq -r, so hex strings keep their quotes off
# only when the caller wants them off -- callers pipe through jq themselves).
rpc_result() {
    rpc_call "$1" "$2" "${3:-[]}" | jq -r '.result // empty'
}

# hex_to_dec <0x...>
hex_to_dec() {
    local h="${1#0x}"
    [ -n "$h" ] || { echo 0; return; }
    echo $((16#$h))
}

run_anvil_aggkit_verification() {
    # verify.sh runs under `set -euo pipefail`, which this function inherits
    # since it is sourced into the same shell. That is the wrong contract for
    # a function whose entire job is to run dozens of independent probes and
    # record which ones failed: a single curl timeout or a `false` return
    # from a plain `$(...)` assignment would otherwise kill the whole script
    # before it ever prints a report. Turn errexit/pipefail off for the rest
    # of this process -- safe because verify.sh, on the anvil-aggkit branch,
    # does nothing else after calling this function but `exit $?` (see the
    # dispatch block near the top of verify.sh), so this can never leak into
    # the default flavor's error handling.
    set +e
    set +o pipefail

    local SNAPSHOT_DIR="$1"
    local SNAPSHOT_ID="$2"
    local SCRIPT_DIR_OF_VERIFY="$3"
    local SUMMARY_JSON="$SNAPSHOT_DIR/summary.json"
    local START_TS
    START_TS=$(date +%s)

    log_step "Snapshot Verification (flavor: anvil-aggkit)"
    log "Snapshot directory: $SNAPSHOT_DIR"

    if [ ! -f "$SUMMARY_JSON" ]; then
        log_error "summary.json not found: $SUMMARY_JSON (required for this flavor)"
        return 1
    fi
    if ! jq -e . "$SUMMARY_JSON" > /dev/null 2>&1; then
        log_error "summary.json is not valid JSON: $SUMMARY_JSON"
        return 1
    fi

    # ------------------------------------------------------------------
    # Read the contract off summary.json -- the single source of truth S8
    # built for exactly this purpose.
    # ------------------------------------------------------------------
    local PROXY_BASE L1_CHAIN_ID L1_NETWORK_ID L1_BRIDGE L1_BLOCK_AT_CAPTURE
    local L2_PREFIXES SETTLEMENT_FREE ERC20_ADDR E2E_WALLET E2E_KEY IMAGES_TAG
    PROXY_BASE=$(jq -r '.proxy.base_url' "$SUMMARY_JSON")
    L1_CHAIN_ID=$(jq -r '.networks.l1.chain_id' "$SUMMARY_JSON")
    L1_NETWORK_ID=$(jq -r '.networks.l1.network_id' "$SUMMARY_JSON")
    L1_BRIDGE=$(jq -r '.networks.l1.contracts.bridge' "$SUMMARY_JSON")
    L1_BLOCK_AT_CAPTURE=$(jq -r '.networks.l1.block_number_at_capture' "$SUMMARY_JSON")
    L2_PREFIXES=$(jq -r '.networks.l2 | keys[]' "$SUMMARY_JSON")
    SETTLEMENT_FREE=$(jq -r '.settlement_free' "$SUMMARY_JSON")
    ERC20_ADDR=$(jq -r '.erc20_address // ""' "$SUMMARY_JSON")
    E2E_WALLET=$(jq -r '.accounts.e2e_wallet.address // ""' "$SUMMARY_JSON")
    E2E_KEY=$(jq -r '.accounts.e2e_wallet.private_key // ""' "$SUMMARY_JSON")
    IMAGES_TAG=$(jq -r '.images.tag // "unknown"' "$SUMMARY_JSON")

    log "Snapshot ID:      $SNAPSHOT_ID"
    log "Enclave:          $(jq -r '.enclave' "$SUMMARY_JSON")"
    log "Image tag:        $IMAGES_TAG"
    log "settlement_free:  $SETTLEMENT_FREE"
    log "haproxy origin:   $PROXY_BASE"
    log "L1 network_id:    $L1_NETWORK_ID"
    log "L2 networks:      $(echo "$L2_PREFIXES" | tr '\n' ' ')"
    log "E2E ERC20:        ${ERC20_ADDR:-none}"

    if [ "$SETTLEMENT_FREE" != "true" ]; then
        log_warn "=================================================================="
        log_warn "THIS SNAPSHOT IS NOT SETTLEMENT-FREE (settlement_free: $SETTLEMENT_FREE)."
        log_warn "agglayer/aggkit internal state was not captured, so a certificate"
        log_warn "that settled BEFORE capture is invisible to the restored agglayer,"
        log_warn "while the chain data (which IS captured) still reflects it. Any"
        log_warn "check below that depends on certificate settlement may fail for"
        log_warn "this specific reason -- that is a property of THIS bundle, not a"
        log_warn "bug in this script. Per plan S8/S10: do not publish a bundle like"
        log_warn "this; only settlement_free:true bundles are sound to ship."
        log_warn "=================================================================="
    fi

    # Pre-pull the cast image once, quietly, so the very first `cast send` in
    # the round trip (TEST 12) does not have first-pull progress noise mixed
    # into a `2>&1` capture that a later `tail -1 | jq` parses as the
    # transaction receipt.
    docker pull -q ghcr.io/foundry-rs/foundry:latest > /dev/null 2>&1

    # ------------------------------------------------------------------
    # TEST 1: referenced images exist locally
    # ------------------------------------------------------------------
    log_step "TEST 1: Docker Images"
    local MISSING_IMAGES=0 IMG
    while IFS= read -r IMG; do
        [ -n "$IMG" ] || continue
        if docker image inspect "$IMG" > /dev/null 2>&1; then
            log_info "  Found: $IMG"
        else
            log_error "  Missing: $IMG"
            MISSING_IMAGES=$((MISSING_IMAGES + 1))
        fi
    done < <(docker compose -f "$SNAPSHOT_DIR/docker-compose.yml" config --images 2>/dev/null)
    anvil_test_result "All referenced images exist locally" "$([ "$MISSING_IMAGES" -eq 0 ] && echo pass || echo fail)"

    # ------------------------------------------------------------------
    # TEST 2: static healthcheck / compose-shape audit (the fix for the
    # always-exit-0 verify-healthchecks.sh, scoped to this flavor).
    # ------------------------------------------------------------------
    log_step "TEST 2: Healthcheck Configuration (static)"
    if "$SCRIPT_DIR_OF_VERIFY/scripts/verify-healthchecks.sh" --flavor anvil-aggkit "$SNAPSHOT_DIR"; then
        anvil_test_result "verify-healthchecks.sh --flavor anvil-aggkit" "pass"
    else
        anvil_test_result "verify-healthchecks.sh --flavor anvil-aggkit" "fail"
    fi

    # ------------------------------------------------------------------
    # TEST 3: start services
    # ------------------------------------------------------------------
    log_step "TEST 3: Start Services"
    local COMPOSE_UP_LOG UP_RC
    COMPOSE_UP_LOG=$(mktemp)
    (cd "$SNAPSHOT_DIR" && docker compose -f docker-compose.yml up -d --wait --wait-timeout 180) \
        > "$COMPOSE_UP_LOG" 2>&1
    UP_RC=$?
    if [ "$UP_RC" -eq 0 ]; then
        anvil_test_result "Services started and reported healthy" "pass"
    else
        anvil_test_result "Services started and reported healthy" "fail"
        log_error "docker compose up -d --wait failed (see $COMPOSE_UP_LOG):"
        tail -n 40 "$COMPOSE_UP_LOG" | while IFS= read -r line; do log_error "  $line"; done
        # No point continuing -- nothing below can pass without a running stack.
        _anvil_aggkit_report "$START_TS"
        return 1
    fi

    # ------------------------------------------------------------------
    # TEST 4: live container health (dynamic -- complements TEST 2's static
    # check with what the containers actually report right now)
    # ------------------------------------------------------------------
    log_step "TEST 4: Live Container Health"
    local UNHEALTHY=0 NAME STATE HEALTH
    while IFS=$'\t' read -r NAME STATE HEALTH; do
        [ -n "$NAME" ] || continue
        if [ "$HEALTH" = "healthy" ] || { [ -z "$HEALTH" ] && [ "$STATE" = "running" ]; }; then
            log_info "  $NAME: $STATE${HEALTH:+ ($HEALTH)}"
        else
            log_error "  $NAME: $STATE${HEALTH:+ ($HEALTH)}"
            UNHEALTHY=$((UNHEALTHY + 1))
        fi
    done < <(cd "$SNAPSHOT_DIR" && docker compose -f docker-compose.yml ps --format json 2>/dev/null \
        | jq -r '[.Name, .State, .Health] | @tsv')
    anvil_test_result "All containers healthy" "$([ "$UNHEALTHY" -eq 0 ] && echo pass || echo fail)"

    # ------------------------------------------------------------------
    # TEST 5: L1 chain checks (contract table row 1)
    # ------------------------------------------------------------------
    log_step "TEST 5: L1 Chain (${PROXY_BASE}/l1rpc)"
    local L1_URL="${PROXY_BASE}/l1rpc"
    local L1_CHAINID_HEX L1_CHAINID_DEC L1_CODE
    L1_CHAINID_HEX=$(rpc_result "$L1_URL" eth_chainId)
    L1_CHAINID_DEC=$(hex_to_dec "$L1_CHAINID_HEX")
    log_info "  eth_chainId = $L1_CHAINID_HEX ($L1_CHAINID_DEC), expected $L1_CHAIN_ID"
    anvil_test_result "L1 chainId == $L1_CHAIN_ID" "$([ "$L1_CHAINID_DEC" = "$L1_CHAIN_ID" ] && echo pass || echo fail)"

    L1_CODE=$(rpc_result "$L1_URL" eth_getCode "[\"$L1_BRIDGE\",\"latest\"]")
    anvil_test_result "L1 eth_getCode(bridge $L1_BRIDGE) != 0x" "$([ -n "$L1_CODE" ] && [ "$L1_CODE" != "0x" ] && echo pass || echo fail)"

    local L1_BLOCK_T0 L1_BLOCK_T1 L1_FIN_T0 L1_FIN_T1
    L1_BLOCK_T0=$(hex_to_dec "$(rpc_result "$L1_URL" eth_blockNumber)")
    L1_FIN_T0=$(hex_to_dec "$(rpc_call "$L1_URL" eth_getBlockByNumber '["finalized",false]' | jq -r '.result.number // "0x0"')")
    sleep 6
    L1_BLOCK_T1=$(hex_to_dec "$(rpc_result "$L1_URL" eth_blockNumber)")
    L1_FIN_T1=$(hex_to_dec "$(rpc_call "$L1_URL" eth_getBlockByNumber '["finalized",false]' | jq -r '.result.number // "0x0"')")
    log_info "  block: $L1_BLOCK_T0 -> $L1_BLOCK_T1 (6s)"
    log_info "  finalized: $L1_FIN_T0 -> $L1_FIN_T1 (6s)"
    anvil_test_result "L1 block progresses" "$([ "$L1_BLOCK_T1" -gt "$L1_BLOCK_T0" ] && echo pass || echo fail)"
    anvil_test_result "L1 finalized advances" "$([ "$L1_FIN_T1" -gt "$L1_FIN_T0" ] && echo pass || echo fail)"

    # ------------------------------------------------------------------
    # TEST 6: each L2 chain (contract table row 2) + restore-time config
    # adaptation (S8 accepted deviation -- must assert it happened AND is
    # correct, not just that aggkit is up).
    # ------------------------------------------------------------------
    local PREFIX
    for PREFIX in $L2_PREFIXES; do
        log_step "TEST 6.$PREFIX: L2-$PREFIX Chain (${PROXY_BASE}/l2rpc-$PREFIX)"
        local L2_URL="${PROXY_BASE}/l2rpc-$PREFIX"
        local L2_CHAIN_ID L2_BRIDGE L2_GER
        L2_CHAIN_ID=$(jq -r --arg p "$PREFIX" '.networks.l2[$p].chain_id' "$SUMMARY_JSON")
        L2_BRIDGE=$(jq -r --arg p "$PREFIX" '.networks.l2[$p].contracts.sovereign_bridge' "$SUMMARY_JSON")
        L2_GER=$(jq -r --arg p "$PREFIX" '.networks.l2[$p].contracts.global_exit_root' "$SUMMARY_JSON")

        local L2_CHAINID_DEC
        L2_CHAINID_DEC=$(hex_to_dec "$(rpc_result "$L2_URL" eth_chainId)")
        log_info "  eth_chainId = $L2_CHAINID_DEC, expected $L2_CHAIN_ID"
        anvil_test_result "L2-$PREFIX chainId == $L2_CHAIN_ID" "$([ "$L2_CHAINID_DEC" = "$L2_CHAIN_ID" ] && echo pass || echo fail)"

        local L2_BRIDGE_CODE L2_GER_CODE
        L2_BRIDGE_CODE=$(rpc_result "$L2_URL" eth_getCode "[\"$L2_BRIDGE\",\"latest\"]")
        L2_GER_CODE=$(rpc_result "$L2_URL" eth_getCode "[\"$L2_GER\",\"latest\"]")
        anvil_test_result "L2-$PREFIX sovereign bridge bytecode present" \
            "$([ -n "$L2_BRIDGE_CODE" ] && [ "$L2_BRIDGE_CODE" != "0x" ] && echo pass || echo fail)"
        anvil_test_result "L2-$PREFIX GER bytecode present" \
            "$([ -n "$L2_GER_CODE" ] && [ "$L2_GER_CODE" != "0x" ] && echo pass || echo fail)"

        local L2_BLOCK_T0 L2_BLOCK_T1 L2_FIN_T0 L2_FIN_T1
        L2_BLOCK_T0=$(hex_to_dec "$(rpc_result "$L2_URL" eth_blockNumber)")
        L2_FIN_T0=$(hex_to_dec "$(rpc_call "$L2_URL" eth_getBlockByNumber '["finalized",false]' | jq -r '.result.number // "0x0"')")
        sleep 4
        L2_BLOCK_T1=$(hex_to_dec "$(rpc_result "$L2_URL" eth_blockNumber)")
        L2_FIN_T1=$(hex_to_dec "$(rpc_call "$L2_URL" eth_getBlockByNumber '["finalized",false]' | jq -r '.result.number // "0x0"')")
        log_info "  block: $L2_BLOCK_T0 -> $L2_BLOCK_T1 (4s); finalized: $L2_FIN_T0 -> $L2_FIN_T1 (4s)"
        anvil_test_result "L2-$PREFIX block progresses" "$([ "$L2_BLOCK_T1" -gt "$L2_BLOCK_T0" ] && echo pass || echo fail)"
        anvil_test_result "L2-$PREFIX finalized advances" "$([ "$L2_FIN_T1" -gt "$L2_FIN_T0" ] && echo pass || echo fail)"

        # ---- S9b: the captured aggkit config is baked VERBATIM. S8 used to
        # repoint rollupCreationBlockNumber / RollupCreationBlockL1 at the L1
        # snapshot block because a restored anvil only held the tip state;
        # extract-state.sh now captures historical states, so that hack is
        # gone and the two invariants worth asserting are:
        #   (a) the LIVE running aggkit still carries the ENCLAVE's creation
        #       block -- i.e. nothing rewrote it behind our back, and
        #   (b) the restored L1 actually answers a state read pinned at that
        #       pre-snapshot block (the exact thing that used to return
        #       BlockOutOfRangeError and kill aggkit / panic agglayer).
        local AGGKIT_SVC
        AGGKIT_SVC=$(jq -r --arg p "$PREFIX" '.networks.l2[$p].aggkit.service' "$SUMMARY_JSON")
        local LIVE_CFG
        LIVE_CFG=$( (cd "$SNAPSHOT_DIR" && docker compose -f docker-compose.yml exec -T "$AGGKIT_SVC" \
            /snapshot/busybox cat /etc/aggkit/config.toml) 2>/dev/null)
        local LIVE_ROLLUP_BLOCK CAPTURED_ROLLUP_BLOCK
        LIVE_ROLLUP_BLOCK=$(echo "$LIVE_CFG" | grep -E '^rollupCreationBlockNumber[[:space:]]*=' | sed -E 's/.*"([0-9]+)".*/\1/')
        CAPTURED_ROLLUP_BLOCK=$(grep -E '^rollupCreationBlockNumber[[:space:]]*=' \
            "$SNAPSHOT_DIR/config/$AGGKIT_SVC/config.toml" 2>/dev/null | sed -E 's/.*"([0-9]+)".*/\1/')
        log_info "  live rollupCreationBlockNumber=$LIVE_ROLLUP_BLOCK, captured=$CAPTURED_ROLLUP_BLOCK (L1 snapshot block $L1_BLOCK_AT_CAPTURE)"
        anvil_test_result "L2-$PREFIX aggkit: rollupCreationBlockNumber baked verbatim (no restore-time rewrite)" \
            "$([ -n "$LIVE_ROLLUP_BLOCK" ] && [ "$LIVE_ROLLUP_BLOCK" = "$CAPTURED_ROLLUP_BLOCK" ] && echo pass || echo fail)"

        # (b) Historical state read: eth_getCode against the L1 bridge pinned
        # at the rollup's creation block. Before S9b this returned
        # `-32602 BlockOutOfRangeError: block height is N but requested was M`.
        local HIST_CALL HIST_CODE HIST_ERR
        HIST_CALL=$(rpc_call "$L1_URL" eth_getCode "[\"$L1_BRIDGE\",\"$(printf '0x%x' "$CAPTURED_ROLLUP_BLOCK")\"]")
        HIST_CODE=$(echo "$HIST_CALL" | jq -r '.result // ""')
        HIST_ERR=$(echo "$HIST_CALL" | jq -r '.error.message // ""')
        log_info "  historical eth_getCode($L1_BRIDGE, block $CAPTURED_ROLLUP_BLOCK): ${HIST_ERR:-${#HIST_CODE} bytes of code}"
        anvil_test_result "L2-$PREFIX: restored L1 serves state reads at the pre-snapshot creation block" \
            "$([ -z "$HIST_ERR" ] && [ -n "$HIST_CODE" ] && [ "$HIST_CODE" != "0x" ] && echo pass || echo fail)"
    done

    # ------------------------------------------------------------------
    # TEST 7: sync-status?network_id=0|1|2, both is_synced AND is_active,
    # both sides -- with polling + timeout (contract table row 3; matches
    # devnetReady.mjs's stricter bar per S9's context pack).
    # ------------------------------------------------------------------
    log_step "TEST 7: Bridge sync-status (network_id 0, 1, 2)"
    local NID SYNC_OK SYNC_JSON SYNC_DEADLINE
    for NID in 0 1 2; do
        SYNC_OK=false
        SYNC_DEADLINE=$(( $(date +%s) + 60 ))
        while [ "$(date +%s)" -lt "$SYNC_DEADLINE" ]; do
            SYNC_JSON=$(curl -s -m 10 "${PROXY_BASE}/aggkitapi/bridge/v1/sync-status?network_id=${NID}")
            if echo "$SYNC_JSON" | jq -e '
                (.l1_info.is_synced == true) and (.l1_info.is_active == true) and
                (.l2_info.is_synced == true) and (.l2_info.is_active == true)
                ' > /dev/null 2>&1; then
                SYNC_OK=true
                break
            fi
            sleep 3
        done
        log_info "  network_id=$NID: $SYNC_JSON"
        anvil_test_result "sync-status network_id=$NID: is_synced && is_active (both sides)" \
            "$([ "$SYNC_OK" = true ] && echo pass || echo fail)"
    done

    # ------------------------------------------------------------------
    # TEST 8: tracker health endpoint (dev-ui docs/deployment.md smoke curl)
    # ------------------------------------------------------------------
    log_step "TEST 8: Tracker Health Endpoint"
    local TRACKER_HEALTH
    TRACKER_HEALTH=$(curl -s -m 10 "${PROXY_BASE}/aggkitapi/tracker/v1/health")
    log_info "  $TRACKER_HEALTH"
    anvil_test_result "tracker/v1/health returns status:ok" \
        "$(echo "$TRACKER_HEALTH" | jq -e '.status == "ok"' > /dev/null 2>&1 && echo pass || echo fail)"

    # ------------------------------------------------------------------
    # TEST 9: aggkit-proxy RetentionPeriod >= 30m (static, from the captured
    # config shipped alongside the bundle)
    # ------------------------------------------------------------------
    log_step "TEST 9: Tracker RetentionPeriod"
    local PROXY_CFG RETENTION RETENTION_OK
    PROXY_CFG=$(find "$SNAPSHOT_DIR/config" -maxdepth 1 -type d -name 'aggkit-proxy*' | head -1)
    RETENTION_OK=false
    if [ -n "$PROXY_CFG" ] && [ -f "$PROXY_CFG/config.toml" ]; then
        RETENTION=$(grep -E '^RetentionPeriod[[:space:]]*=' "$PROXY_CFG/config.toml" | sed -E 's/.*"([^"]*)".*/\1/')
        log_info "  RetentionPeriod = $RETENTION"
        case "$RETENTION" in
            *h) RETENTION_OK=true ;;                                    # any number of hours
            *m) [ "${RETENTION%m}" -ge 30 ] 2>/dev/null && RETENTION_OK=true ;;
        esac
    else
        log_error "  aggkit-proxy config.toml not found under $SNAPSHOT_DIR/config"
    fi
    anvil_test_result "aggkit-proxy RetentionPeriod >= 30m" "$([ "$RETENTION_OK" = true ] && echo pass || echo fail)"

    # ------------------------------------------------------------------
    # TEST 10: haproxy CORS preflight on every route, from both dev-ui dev
    # origins (contract table row 5)
    # ------------------------------------------------------------------
    log_step "TEST 10: CORS Preflight"
    local ROUTE ORIGIN CORS_OK ROUTES=("/l1rpc")
    for PREFIX in $L2_PREFIXES; do ROUTES+=("/l2rpc-$PREFIX"); done
    ROUTES+=("/aggkitapi")
    for ROUTE in "${ROUTES[@]}"; do
        for ORIGIN in "http://localhost:3000" "http://localhost:3100"; do
            local RESP CODE ACAO
            RESP=$(curl -s -m 10 -i -X OPTIONS "${PROXY_BASE}${ROUTE}" \
                -H "Origin: $ORIGIN" -H "Access-Control-Request-Method: POST")
            CODE=$(echo "$RESP" | head -1 | grep -oE '[0-9]{3}')
            ACAO=$(echo "$RESP" | grep -i '^access-control-allow-origin:' | tr -d '\r')
            CORS_OK=false
            [ "$CODE" = "204" ] && [ -n "$ACAO" ] && CORS_OK=true
            anvil_test_result "CORS preflight OPTIONS $ROUTE from $ORIGIN" "$([ "$CORS_OK" = true ] && echo pass || echo fail)"

            # Contract table row 5 is "OPTIONS preflight + POST JSON-RPC" --
            # the preflight alone is not the whole requirement. Confirm the
            # ACTUAL request (not just its preflight) carries CORS headers
            # too, using a real POST JSON-RPC for the rpc routes and a real
            # GET REST call for /aggkitapi.
            local ACTUAL_RESP ACTUAL_CODE ACTUAL_ACAO ACTUAL_OK=false
            if [ "$ROUTE" = "/aggkitapi" ]; then
                ACTUAL_RESP=$(curl -s -m 10 -i "${PROXY_BASE}${ROUTE}/bridge/v1/sync-status?network_id=0" -H "Origin: $ORIGIN")
            else
                ACTUAL_RESP=$(curl -s -m 10 -i -X POST "${PROXY_BASE}${ROUTE}" -H "Origin: $ORIGIN" \
                    -H "Content-Type: application/json" \
                    --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')
            fi
            ACTUAL_CODE=$(echo "$ACTUAL_RESP" | head -1 | grep -oE '[0-9]{3}')
            ACTUAL_ACAO=$(echo "$ACTUAL_RESP" | grep -i '^access-control-allow-origin:' | tr -d '\r')
            [ "$ACTUAL_CODE" = "200" ] && [ -n "$ACTUAL_ACAO" ] && ACTUAL_OK=true
            anvil_test_result "CORS actual request $ROUTE from $ORIGIN carries CORS headers" \
                "$([ "$ACTUAL_OK" = true ] && echo pass || echo fail)"
        done
    done

    # ------------------------------------------------------------------
    # TEST 11: dev-ui /config.json is valid
    # ------------------------------------------------------------------
    log_step "TEST 11: dev-ui /config.json"
    local DEVUI_CONFIG DEVUI_CONFIG_FILE
    DEVUI_CONFIG_FILE=$(mktemp)
    DEVUI_CONFIG=$(curl -s -m 10 "${PROXY_BASE}/config.json")
    echo "$DEVUI_CONFIG" > "$DEVUI_CONFIG_FILE"
    local DEVUI_JSON_OK=false DEVUI_SCHEMA_OK=false
    if echo "$DEVUI_CONFIG" | jq -e . > /dev/null 2>&1; then
        DEVUI_JSON_OK=true
    fi
    anvil_test_result "dev-ui /config.json is valid JSON" "$([ "$DEVUI_JSON_OK" = true ] && echo pass || echo fail)"

    if [ "$DEVUI_JSON_OK" = true ]; then
        # Prefer dev-ui's own scripts/validateConfig.mjs when a checkout is
        # discoverable (overridable via DEVUI_REPO_PATH; not assumed present
        # on GH runners for THIS step -- S12/S13 own that wiring). Falls back
        # to a portable structural check so this script has no hard external
        # dependency.
        local DEVUI_REPO="${DEVUI_REPO_PATH:-}"
        if [ -z "$DEVUI_REPO" ]; then
            for _cand in "/home/brolygon/repos/agglayer/agglayer-dev-ui" "../agglayer-dev-ui" "../../agglayer/agglayer-dev-ui"; do
                if [ -f "$_cand/scripts/validateConfig.mjs" ]; then DEVUI_REPO="$_cand"; break; fi
            done
        fi
        if [ -n "$DEVUI_REPO" ] && [ -f "$DEVUI_REPO/scripts/validateConfig.mjs" ] && command -v node > /dev/null 2>&1; then
            local VALIDATE_OUT
            VALIDATE_OUT=$(cd "$DEVUI_REPO" && node ./scripts/validateConfig.mjs "$DEVUI_CONFIG_FILE" 2>&1)
            log_info "  validateConfig.mjs: $VALIDATE_OUT"
            anvil_test_result "dev-ui /config.json passes scripts/validateConfig.mjs" \
                "$(echo "$VALIDATE_OUT" | grep -q "validation passed" && echo pass || echo fail)"
        else
            log_warn "  dev-ui checkout with scripts/validateConfig.mjs not found; falling back to a structural check"
            # Matches the real schema emitted by
            # static_files/additional_services/bridge-ui/aggkit-dev-ui-config.json.tmpl:
            # "chains" is an OBJECT keyed by chain name (not an array), and
            # "aggkitBridgeApis" lives inside appModes.configs.<mode>, not at
            # the top level. This exact mismatch was only ever masked on dev
            # machines that happen to have an agglayer-dev-ui checkout (which
            # takes the validateConfig.mjs branch above instead) -- caught by
            # S11's first real CI run, which has no such checkout.
            DEVUI_SCHEMA_OK=$(echo "$DEVUI_CONFIG" | jq -e '
                (has("chains") and (.chains | type == "object") and (.chains | length > 0)) and
                (has("appModes") and (.appModes | has("configs")) and
                 (.appModes.configs | type == "object") and (.appModes.configs | length > 0) and
                 (.appModes.configs | to_entries[0].value | has("aggkitBridgeApis")))
                ' > /dev/null 2>&1 && echo true || echo false)
            anvil_test_result "dev-ui /config.json has required keys (chains object; appModes.configs.<mode>.aggkitBridgeApis)" \
                "$([ "$DEVUI_SCHEMA_OK" = true ] && echo pass || echo fail)"
        fi
    fi
    rm -f "$DEVUI_CONFIG_FILE"

    # ------------------------------------------------------------------
    # TEST 12: scripted bridge round trip
    # ------------------------------------------------------------------
    _anvil_aggkit_bridge_roundtrip "$SUMMARY_JSON" "$PROXY_BASE" "$L1_BRIDGE" "$E2E_WALLET" "$E2E_KEY" "$SETTLEMENT_FREE" "$L1_NETWORK_ID"

    _anvil_aggkit_report "$START_TS"
}

# ============================================================================
# Bridge round trip: L1->L2 (autoclaimed) then L2->L1 (ready-to-claim, then
# manually claimed via cast). See module doc for the F1 / leaf_index traps.
# ============================================================================
_anvil_aggkit_bridge_roundtrip() {
    local SUMMARY_JSON="$1" PROXY_BASE="$2" L1_BRIDGE="$3" WALLET="$4" KEY="$5" SETTLEMENT_FREE="$6" L1_NETWORK_ID="$7"

    log_step "TEST 12: Bridge Round Trip (L1->L2 autoclaim, L2->L1 manual claim)"

    if [ -z "$WALLET" ] || [ -z "$KEY" ]; then
        log_error "  E2E wallet/key not present in summary.json -- cannot run the round trip"
        anvil_test_result "Bridge round trip" "fail"
        return
    fi

    # The first L2 (by prefix) is used as the source/destination for both
    # legs; any autoclaim-destination network from the contract table works
    # (1 or 2), so this deliberately does not hardcode "001".
    local PREFIX
    PREFIX=$(jq -r '.networks.l2 | keys | sort | first' "$SUMMARY_JSON")
    local L1_URL="${PROXY_BASE}/l1rpc"
    local L2_URL="${PROXY_BASE}/l2rpc-${PREFIX}"
    local NETWORK_ID
    NETWORK_ID=$(jq -r --arg p "$PREFIX" '.networks.l2[$p].network_id' "$SUMMARY_JSON")
    local L2_BRIDGE
    L2_BRIDGE=$(jq -r --arg p "$PREFIX" '.networks.l2[$p].contracts.sovereign_bridge' "$SUMMARY_JSON")

    # ---- Leg 1: L1 -> L2 (must autoclaim) ----
    log "  Leg 1: L1 -> L2-$PREFIX (network $NETWORK_ID), 0.01 native ETH"
    local SEND1 TX1 RC1
    SEND1=$(_verify_cast send --json --rpc-url "$L1_URL" --private-key "$KEY" "$L1_BRIDGE" \
        'bridgeAsset(uint32,address,uint256,address,bool,bytes)' \
        "$NETWORK_ID" "$WALLET" 10000000000000000 0x0000000000000000000000000000000000000000 true 0x \
        --value 10000000000000000 2>&1)
    TX1=$(echo "$SEND1" | tail -1 | jq -r '.transactionHash // empty' 2>/dev/null)
    RC1=$(echo "$SEND1" | tail -1 | jq -r '.status // empty' 2>/dev/null)
    if [ -z "$TX1" ] || [ "$RC1" != "0x1" ]; then
        log_error "  L1->L2 bridgeAsset send failed: $SEND1"
        anvil_test_result "Bridge round trip: L1->L2 deposit sent" "fail"
        return
    fi
    log_info "  tx: $TX1"
    anvil_test_result "Bridge round trip: L1->L2 deposit sent" "pass"

    local L1L2_STATE
    L1L2_STATE=$(_poll_tracker "$PROXY_BASE" "$L1_NETWORK_ID" "$TX1" 90 "L1->L2")
    local L1L2_STATUS L1L2_LAST_STEP
    L1L2_STATUS=$(echo "$L1L2_STATE" | jq -r '.tracking_status // "?"')
    L1L2_LAST_STEP=$(echo "$L1L2_STATE" | jq -r '.all_steps[-1].step_name // "?"')
    log_info "  tracker terminal: tracking_status=$L1L2_STATUS last_step=$L1L2_LAST_STEP"
    anvil_test_result "Bridge round trip: L1->L2 autoclaimed (tracker finished/Claimed)" \
        "$([ "$L1L2_STATUS" = "finished" ] && [ "$L1L2_LAST_STEP" = "Claimed" ] && echo pass || echo fail)"

    # ---- Leg 2: L2-001 -> L1 (must stay manual: parks at WaitingClaim) ----
    log "  Leg 2: L2-$PREFIX -> L1 (network $L1_NETWORK_ID), 0.001 native ETH (uses the balance Leg 1 just claimed in)"
    local SEND2 TX2 RC2
    SEND2=$(_verify_cast send --json --rpc-url "$L2_URL" --private-key "$KEY" "$L2_BRIDGE" \
        'bridgeAsset(uint32,address,uint256,address,bool,bytes)' \
        "$L1_NETWORK_ID" "$WALLET" 1000000000000000 0x0000000000000000000000000000000000000000 true 0x \
        --value 1000000000000000 2>&1)
    TX2=$(echo "$SEND2" | tail -1 | jq -r '.transactionHash // empty' 2>/dev/null)
    RC2=$(echo "$SEND2" | tail -1 | jq -r '.status // empty' 2>/dev/null)
    if [ -z "$TX2" ] || [ "$RC2" != "0x1" ]; then
        log_error "  L2->L1 bridgeAsset send failed: $SEND2"
        anvil_test_result "Bridge round trip: L2->L1 deposit sent" "fail"
        return
    fi
    log_info "  tx: $TX2"
    anvil_test_result "Bridge round trip: L2->L1 deposit sent" "pass"

    # Poll to "ready to claim" (WaitingClaim done or in progress with a
    # settled certificate) -- budget >=5 min per S4b/S6 (agglayer epoch
    # cadence 15s, settlement waits on SafeBlock; full round trip ~3.5 min
    # measured in S4b). Distinguish a genuinely-stuck InError certificate
    # (fails fast after it repeats unchanged) from ordinary "still pending".
    local DEADLINE=$(( $(date +%s) + 300 ))
    local READY=false INERROR_STREAK=0 LAST_CERT_STATUS="" L2L1_STATE
    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        L2L1_STATE=$(curl -s -m 10 "${PROXY_BASE}/aggkitapi/tracker/v1/network/${NETWORK_ID}/tx/${TX2}")
        local WC_STATUS CERT_STATUS_STRING STEP_ERR_TYPE
        WC_STATUS=$(echo "$L2L1_STATE" | jq -r '.all_steps[] | select(.step_name=="WaitingClaim") | .status')
        CERT_STATUS_STRING=$(echo "$L2L1_STATE" | jq -r '.all_steps[] | select(.step_name=="CertificatePending") | .result.status_string // "?"')
        STEP_ERR_TYPE=$(echo "$L2L1_STATE" | jq -r '.all_steps[] | select(.step_name=="CertificatePending") | .error.error_type_string // "?"')
        log_info "  poll: WaitingClaim=$WC_STATUS CertificatePending.status_string=$CERT_STATUS_STRING step_error=$STEP_ERR_TYPE"

        if [ "$WC_STATUS" = "done" ] || [ "$WC_STATUS" = "inProgress" ]; then
            READY=true
            break
        fi
        if [ "$CERT_STATUS_STRING" = "InError" ]; then
            if [ "$CERT_STATUS_STRING" = "$LAST_CERT_STATUS" ]; then
                INERROR_STREAK=$((INERROR_STREAK + 1))
            else
                INERROR_STREAK=1
            fi
            # Three consecutive identical InError observations (~15s) without
            # any progress: this is not the documented "transient, self-
            # resolving" retry pattern (which surfaces as a STEP-level error
            # with error_type_string:"transient", not a certificate-level
            # InError result) -- treat it as a real, non-recoverable failure
            # rather than burning the whole 5-minute budget on it.
            if [ "$INERROR_STREAK" -ge 3 ]; then
                log_error "  Certificate stuck in InError for 3+ consecutive polls: $L2L1_STATE"
                log_error "  This is a restore-time hazard in the snapshot itself, not something this"
                log_error "  verify script can work around -- observed root causes (S9 investigation):"
                log_error "  (a) settlement_free=false: agglayer's (uncaptured) DB believes no cert has"
                log_error "      ever settled while the restored chain's real history disagrees, so a new"
                log_error "      certificate's declared prev_local_exit_root mismatches what agglayer"
                log_error "      independently computes (TypeConversionError/MismatchPrevLocalExitRoot)."
                log_error "  (b) a state dump captured WITHOUT historical states (the S9b defect):"
                log_error "      agglayer probes its settlement signer's nonce inclusion at the"
                log_error "      pre-snapshot L1 block holding that wallet's earlier tx. If the restored"
                log_error "      anvil carries only the tip state that returns -32602"
                log_error "      BlockOutOfRangeError -> SettlementError(\"settlement job watcher closed"
                log_error "      before producing a result\") -> panic at"
                log_error "      crates/agglayer-settlement-service/src/settlement_task.rs -> InError."
                log_error "      Check with: jq '.historical_states|length' state/*.json -- it must be"
                log_error "      non-zero (extract-state.sh captures with anvil_dumpState(true))."
                log_error "      This settlement_free=$SETTLEMENT_FREE bundle hit one of these."
                log_error "  Neither is a defect in this verify script; both are capture-time defects"
                log_error "  in the bundle itself."
                break
            fi
        else
            INERROR_STREAK=0
        fi
        LAST_CERT_STATUS="$CERT_STATUS_STRING"
        sleep 5
    done

    anvil_test_result "Bridge round trip: L2->L1 reaches ready-to-claim (WaitingClaim)" "$([ "$READY" = true ] && echo pass || echo fail)"
    if [ "$READY" != true ]; then
        anvil_test_result "Bridge round trip: L2->L1 manual claim via cast" "fail"
        return
    fi

    # Confirm it PERSISTS at ready-to-claim rather than autoclaiming (network
    # 0 must stay manual -- manual-claim.spec.ts:110-114's 60s assertion).
    sleep 15
    local STILL_WAITING
    STILL_WAITING=$(curl -s -m 10 "${PROXY_BASE}/aggkitapi/tracker/v1/network/${NETWORK_ID}/tx/${TX2}" \
        | jq -r '.all_steps[] | select(.step_name=="WaitingClaim") | .status')
    anvil_test_result "Bridge round trip: L2->L1 does NOT autoclaim (still WaitingClaim after 15s)" \
        "$([ "$STILL_WAITING" != "done" ] && echo pass || echo fail)"

    # ---- Manual claim via cast, sourced entirely from the bridges REST
    # listing + claim-proof, per the F1 comment and the S4b recipe. ----
    local BRIDGES_JSON DEPOSIT
    BRIDGES_JSON=$(curl -s -m 10 "${PROXY_BASE}/aggkitapi/bridge/v1/bridges?network_id=${NETWORK_ID}")
    DEPOSIT=$(echo "$BRIDGES_JSON" | jq -c --arg h "$TX2" '.bridges[] | select(.tx_hash == $h)')
    if [ -z "$DEPOSIT" ]; then
        log_error "  Could not find deposit $TX2 in bridges?network_id=$NETWORK_ID: $BRIDGES_JSON"
        anvil_test_result "Bridge round trip: L2->L1 manual claim via cast" "fail"
        return
    fi
    local DEPOSIT_COUNT GLOBAL_INDEX
    # NOTE (F1, S6 finding): origin_network/origin_address below are read
    # straight from this specific deposit's bridges-listing entry -- the
    # ASSET's origin network (0 for native ETH), never $NETWORK_ID (the
    # chain the deposit was submitted ON). Passing $NETWORK_ID here would
    # revert InvalidSmtProof.
    local ORIGIN_NETWORK ORIGIN_ADDRESS DEST_NETWORK DEST_ADDRESS AMOUNT METADATA
    ORIGIN_NETWORK=$(echo "$DEPOSIT" | jq -r '.origin_network')
    ORIGIN_ADDRESS=$(echo "$DEPOSIT" | jq -r '.origin_address')
    DEST_NETWORK=$(echo "$DEPOSIT" | jq -r '.destination_network')
    DEST_ADDRESS=$(echo "$DEPOSIT" | jq -r '.destination_address')
    AMOUNT=$(echo "$DEPOSIT" | jq -r '.amount')
    METADATA=$(echo "$DEPOSIT" | jq -r '.metadata')
    DEPOSIT_COUNT=$(echo "$DEPOSIT" | jq -r '.deposit_count')
    GLOBAL_INDEX=$(echo "$DEPOSIT" | jq -r '.global_index')
    log_info "  deposit: deposit_count=$DEPOSIT_COUNT global_index=$GLOBAL_INDEX origin_network=$ORIGIN_NETWORK (asset origin, NOT $NETWORK_ID)"

    # leaf_index for claim-proof is the L1-INFO-TREE index, not deposit_count
    # (S4b trap). A wrong leaf_index here is indistinguishable from "not yet
    # claimable" (both 500), so this is fetched fresh every time rather than
    # cached/guessed.
    local LEAF_INDEX
    LEAF_INDEX=$(curl -s -m 10 "${PROXY_BASE}/aggkitapi/bridge/v1/l1-info-tree-index?network_id=${NETWORK_ID}&deposit_count=${DEPOSIT_COUNT}")
    if ! [[ "$LEAF_INDEX" =~ ^[0-9]+$ ]]; then
        log_error "  l1-info-tree-index did not return a plain integer: $LEAF_INDEX"
        anvil_test_result "Bridge round trip: L2->L1 manual claim via cast" "fail"
        return
    fi
    log_info "  leaf_index (L1 info tree) = $LEAF_INDEX"

    local CLAIM_PROOF CP_DEADLINE=$(( $(date +%s) + 120 ))
    while [ "$(date +%s)" -lt "$CP_DEADLINE" ]; do
        CLAIM_PROOF=$(curl -s -m 10 "${PROXY_BASE}/aggkitapi/bridge/v1/claim-proof?network_id=${NETWORK_ID}&leaf_index=${LEAF_INDEX}&deposit_count=${DEPOSIT_COUNT}")
        if echo "$CLAIM_PROOF" | jq -e '.proof_local_exit_root and .proof_rollup_exit_root and .l1_info_tree_leaf' > /dev/null 2>&1; then
            break
        fi
        sleep 5
    done
    if ! echo "$CLAIM_PROOF" | jq -e '.proof_local_exit_root and .proof_rollup_exit_root and .l1_info_tree_leaf' > /dev/null 2>&1; then
        log_error "  claim-proof never became available: $CLAIM_PROOF"
        anvil_test_result "Bridge round trip: L2->L1 manual claim via cast" "fail"
        return
    fi

    local LOCAL_PROOF ROLLUP_PROOF MAINNET_EXIT_ROOT ROLLUP_EXIT_ROOT
    LOCAL_PROOF=$(echo "$CLAIM_PROOF" | jq -c '.proof_local_exit_root | "[" + join(",") + "]"' | tr -d '"')
    ROLLUP_PROOF=$(echo "$CLAIM_PROOF" | jq -c '.proof_rollup_exit_root | "[" + join(",") + "]"' | tr -d '"')
    MAINNET_EXIT_ROOT=$(echo "$CLAIM_PROOF" | jq -r '.l1_info_tree_leaf.mainnet_exit_root')
    ROLLUP_EXIT_ROOT=$(echo "$CLAIM_PROOF" | jq -r '.l1_info_tree_leaf.rollup_exit_root')

    local CLAIM_SEND CLAIM_TX CLAIM_RC
    CLAIM_SEND=$(_verify_cast send --json --rpc-url "$L1_URL" --private-key "$KEY" "$L1_BRIDGE" \
        'claimAsset(bytes32[32],bytes32[32],uint256,bytes32,bytes32,uint32,address,uint32,address,uint256,bytes)' \
        "$LOCAL_PROOF" "$ROLLUP_PROOF" "$GLOBAL_INDEX" "$MAINNET_EXIT_ROOT" "$ROLLUP_EXIT_ROOT" \
        "$ORIGIN_NETWORK" "$ORIGIN_ADDRESS" "$DEST_NETWORK" "$DEST_ADDRESS" "$AMOUNT" "$METADATA" 2>&1)
    CLAIM_TX=$(echo "$CLAIM_SEND" | tail -1 | jq -r '.transactionHash // empty' 2>/dev/null)
    CLAIM_RC=$(echo "$CLAIM_SEND" | tail -1 | jq -r '.status // empty' 2>/dev/null)
    log_info "  claimAsset -> tx=$CLAIM_TX status=$CLAIM_RC"
    if [ -z "$CLAIM_TX" ] || [ "$CLAIM_RC" != "0x1" ]; then
        log_error "  claimAsset send failed: $CLAIM_SEND"
        anvil_test_result "Bridge round trip: L2->L1 manual claim via cast" "fail"
        return
    fi

    local IS_CLAIMED
    IS_CLAIMED=$(_verify_cast call --rpc-url "$L1_URL" "$L1_BRIDGE" \
        'isClaimed(uint32,uint32)(bool)' "$DEPOSIT_COUNT" "$ORIGIN_NETWORK" 2>&1 | tail -1)
    log_info "  isClaimed($DEPOSIT_COUNT, $ORIGIN_NETWORK) = $IS_CLAIMED"
    anvil_test_result "Bridge round trip: L2->L1 manual claim via cast (isClaimed == true)" \
        "$([ "$IS_CLAIMED" = "true" ] && echo pass || echo fail)"
}

# _poll_tracker <proxy_base> <network_id> <tx_hash> <timeout_s> <label>
# Polls GET /tracker/v1/network/{network_id}/tx/{tx_hash} to a TERMINAL
# state (tracking_status "finished", or "error" with a non-transient step),
# tolerating transient step errors indefinitely within the timeout. Echoes
# the last JSON payload seen.
_poll_tracker() {
    local proxy_base="$1" network_id="$2" tx_hash="$3" timeout_s="$4" label="$5"
    local deadline=$(( $(date +%s) + timeout_s ))
    local resp status
    while [ "$(date +%s)" -lt "$deadline" ]; do
        resp=$(curl -s -m 10 "${proxy_base}/aggkitapi/tracker/v1/network/${network_id}/tx/${tx_hash}")
        status=$(echo "$resp" | jq -r '.tracking_status // "?"')
        if [ "$status" = "finished" ]; then
            echo "$resp"
            return 0
        fi
        # A tracking_status of "error" is only terminal if the offending
        # step's error is NOT transient; a transient one self-resolves and
        # tracking_status flips back to "running" on a later poll (S1/S6).
        if [ "$status" = "error" ]; then
            local err_type
            err_type=$(echo "$resp" | jq -r '[.all_steps[]? | select(.status=="error") | .error.error_type_string] | last // "?"')
            log_info "  [$label] tracking_status=error step_error_type=$err_type (tolerating unless non-transient)"
            if [ "$err_type" != "transient" ] && [ "$err_type" != "?" ]; then
                echo "$resp"
                return 1
            fi
        fi
        sleep 3
    done
    echo "$resp"
    return 1
}

# ============================================================================
# Final report + exit code
# ============================================================================
_anvil_aggkit_report() {
    local start_ts="$1" end_ts elapsed
    end_ts=$(date +%s)
    elapsed=$((end_ts - start_ts))

    log_step "VERIFICATION RESULTS (flavor: anvil-aggkit)"
    echo ""
    log "Tests run:    $ANVIL_TESTS_TOTAL"
    log "Tests passed: $ANVIL_TESTS_PASSED"
    log "Tests failed: $ANVIL_TESTS_FAILED"
    log "Elapsed:      ${elapsed}s"
    echo ""

    if [ "$ANVIL_TESTS_FAILED" -eq 0 ]; then
        log_step "✓ VERIFICATION PASSED"
        return 0
    else
        log_step "✗ VERIFICATION FAILED"
        log_error "$ANVIL_TESTS_FAILED test(s) failed"
        return 1
    fi
}
