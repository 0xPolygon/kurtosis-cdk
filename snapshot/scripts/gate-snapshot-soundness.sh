#!/usr/bin/env bash
#
# Snapshot Soundness Gate
#
# Machine-checkable pre-publish gate for the anvil-aggkit flavor's
# state/state-metadata.json and the state files next to it. Three independent
# invariants, all required for a restored bundle to be able to settle
# certificates at all:
#
#   1. settlement_free == true
#      agglayer/aggkit internal databases are never captured, so restoring
#      chain state that already contains bridge/certificate activity is
#      unsound (docs/docs/advanced/snapshot.md's existing constraint, carried
#      over to this flavor). A null (not checked) counts as a failure.
#
#   2. the expected chain set is present: exactly one L1 and at least one L2
#      (exactly N with --expect-l2 N), each with a unique service name, a
#      network id (L1: 0) and a state file under state/.
#
#   3. every chain's state file has accounts and historical_states > 0.
#      anvil_dumpState is captured with preserve_historical_states, and a dump
#      with historical_states == 0 can only serve eth_call/eth_getCode at the
#      tip -- any component (e.g. agglayer's settlement-signer nonce probe)
#      that reads state at a pre-snapshot block then panics with
#      BlockOutOfRangeError. The count is recomputed from the state file; the
#      value the metadata claims must match it.
#
# This is deliberately a SEPARATE, explicit CI gate on top of the checks
# extract-state.sh/build-images.sh already perform at capture/bake time, so it
# also catches a bundle that was produced by an older/bypassed snapshot.sh or
# copied in from elsewhere. Only invariant 3 is recomputed from the state
# files: settlement_free and the chain set (roles, network ids, L2 count) are
# read from the metadata as extract-state.sh recorded them, so a hand-edited
# metadata file is not detected. The state files are looked up relative to the
# bundle root, the parent directory of the one holding the metadata.
# gate-snapshot-soundness_test.sh covers the failing cases.
#
# Usage: gate-snapshot-soundness.sh [--expect-l2 <N>] <state-metadata.json>
#
# Exit 0  -- all invariants hold, safe to publish.
# Exit 1  -- one or more invariants violated, or the input is missing/malformed.

set -euo pipefail

EXPECT_L2=""
while [ $# -gt 0 ]; do
    case "$1" in
        --expect-l2)
            if [ $# -lt 2 ] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "ERROR: --expect-l2 needs a positive integer" >&2
                exit 1
            fi
            EXPECT_L2="$2"
            shift 2
            ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -ne 1 ]; then
    echo "Usage: $0 [--expect-l2 <N>] <state-metadata.json>" >&2
    exit 1
fi

STATE_METADATA="$1"
BUNDLE_ROOT="$(cd "$(dirname "$STATE_METADATA")/.." 2>/dev/null && pwd || echo "")"

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required" >&2
    exit 1
fi

if [ ! -f "$STATE_METADATA" ]; then
    echo "ERROR: state metadata not found: $STATE_METADATA" >&2
    exit 1
fi

if ! jq -e . "$STATE_METADATA" > /dev/null 2>&1; then
    echo "ERROR: $STATE_METADATA is not valid JSON" >&2
    exit 1
fi

FAIL=0

echo "=================================================================="
echo "Snapshot soundness gate: $STATE_METADATA"
echo "=================================================================="

# --- Gate 1: settlement_free -------------------------------------------
# NOTE: deliberately NOT `.settlement_free // "missing"` -- jq's `//`
# alternative operator treats a literal `false` the same as `null`/absent,
# so that expression would misreport a genuine `settlement_free: false` as
# "missing". `has(...)` distinguishes "key absent" from "key present and
# false".
SETTLEMENT_FREE=$(jq -r 'if has("settlement_free") then (.settlement_free | tostring) else "missing" end' "$STATE_METADATA")

if [ "$SETTLEMENT_FREE" = "true" ]; then
    echo "[PASS] settlement_free == true"
else
    echo "[FAIL] settlement_free == $SETTLEMENT_FREE (must be true)" >&2
    echo "       agglayer/aggkit internal databases are not captured, so" >&2
    echo "       restoring chain state that already contains bridge/" >&2
    echo "       certificate activity is unsound. Certificate state at" >&2
    echo "       capture time:" >&2
    jq -r '.agglayer_certificates[]? | "         network \(.network_id): latest known certificate height \(.latest_known_certificate_height) (\(.status))"' \
        "$STATE_METADATA" >&2 || true
    FAIL=1
fi

# --- Gate 2: the expected chain set ------------------------------------
# `.chains | length` is NOT sufficient on its own: jq's `length` returns a
# number's absolute value and a string's character count, so `"chains": 5` and
# `"chains": "abc"` both yield a positive count -- and then `.chains[]` errors,
# the loop below runs zero times, FAIL stays 0 and the gate PASSES vacuously.
# Require an actual array.
CHAIN_COUNT=$(jq -r 'if (.chains | type) == "array" then (.chains | length) else -1 end' "$STATE_METADATA" 2>/dev/null || echo -1)

if ! [[ "$CHAIN_COUNT" =~ ^-?[0-9]+$ ]] || [ "$CHAIN_COUNT" -lt 0 ]; then
    echo "[FAIL] .chains is missing or is not an array -- nothing to gate on" >&2
    FAIL=1
elif [ "$CHAIN_COUNT" -eq 0 ]; then
    echo "[FAIL] .chains is an empty array -- nothing to gate on" >&2
    FAIL=1
else
    L1_COUNT=$(jq -r '[.chains[] | select(.role == "l1")] | length' "$STATE_METADATA" 2>/dev/null || echo -1)
    L2_COUNT=$(jq -r '[.chains[] | select(.role == "l2")] | length' "$STATE_METADATA" 2>/dev/null || echo -1)
    UNIQUE_SERVICES=$(jq -r '[.chains[].service] | unique | length' "$STATE_METADATA" 2>/dev/null || echo -1)
    if [ "$L1_COUNT" = "1" ]; then
        echo "[PASS] exactly one L1 chain"
    else
        echo "[FAIL] expected exactly one chain with role l1, found $L1_COUNT" >&2
        FAIL=1
    fi
    if [ -n "$EXPECT_L2" ]; then
        if [ "$L2_COUNT" = "$EXPECT_L2" ]; then
            echo "[PASS] $L2_COUNT L2 chain(s), as expected"
        else
            echo "[FAIL] expected $EXPECT_L2 chain(s) with role l2, found $L2_COUNT" >&2
            FAIL=1
        fi
    elif [ "$L2_COUNT" -ge 1 ] 2>/dev/null; then
        echo "[PASS] $L2_COUNT L2 chain(s)"
    else
        echo "[FAIL] expected at least one chain with role l2, found $L2_COUNT" >&2
        FAIL=1
    fi
    if [ "$UNIQUE_SERVICES" != "$CHAIN_COUNT" ]; then
        echo "[FAIL] chain service names are not unique or not all present ($UNIQUE_SERVICES distinct of $CHAIN_COUNT)" >&2
        FAIL=1
    fi
    if [ "$(jq -r '[.chains[] | select(.role == "l1") | .network_id] | all(. == 0)' "$STATE_METADATA" 2>/dev/null)" != "true" ]; then
        echo "[FAIL] the L1 chain must have network_id 0" >&2
        FAIL=1
    fi
    if [ "$(jq -r '[.chains[] | select(.role == "l2") | .network_id] | (all(type == "number" and . > 0)) and (length == (unique | length))' "$STATE_METADATA" 2>/dev/null)" != "true" ]; then
        echo "[FAIL] every L2 chain needs a distinct positive numeric network_id" >&2
        FAIL=1
    fi
fi

# --- Gate 3: state files, recomputed ------------------------------------
if [ "$CHAIN_COUNT" -gt 0 ] 2>/dev/null; then
    SEEN_CHAINS=0
    while IFS=$'\t' read -r service state_file claimed; do
        SEEN_CHAINS=$((SEEN_CHAINS + 1))
        if ! [[ "$state_file" =~ ^state/[A-Za-z0-9._-]+\.json$ ]]; then
            echo "[FAIL] $service: state_file '$state_file' is missing or not a state/<name>.json path" >&2
            FAIL=1
            continue
        fi
        state_path="$BUNDLE_ROOT/$state_file"
        if [ -z "$BUNDLE_ROOT" ] || [ ! -s "$state_path" ]; then
            echo "[FAIL] $service: state file not found or empty: $state_path" >&2
            FAIL=1
            continue
        fi
        # Guarded by a type check: jq's `length` on a number returns its
        # absolute value and on a string its character count, so a malformed
        # `"historical_states": 1` would pass a bare `length > 0`.
        accounts=$(jq -r 'if (.accounts | type) == "object" then (.accounts | length) else 0 end' "$state_path" 2>/dev/null || echo 0)
        historical=$(jq -r 'if (.historical_states | type) as $t | ($t == "object" or $t == "array") then (.historical_states | length) else 0 end' "$state_path" 2>/dev/null || echo 0)
        if ! [[ "$accounts" =~ ^[0-9]+$ ]] || [ "$accounts" -eq 0 ]; then
            echo "[FAIL] $service: $state_file has no accounts (not an anvil dump)" >&2
            FAIL=1
        elif ! [[ "$historical" =~ ^[0-9]+$ ]] || [ "$historical" -eq 0 ]; then
            echo "[FAIL] $service: $state_file has historical_states == $historical (must be > 0 -- a restored anvil with zero preserved historical states cannot serve eth_call at any pre-snapshot block, so agglayer's settlement-signer nonce probe panics with BlockOutOfRangeError)" >&2
            FAIL=1
        elif [ "$claimed" != "$historical" ]; then
            echo "[FAIL] $service: metadata claims historical_states == $claimed but $state_file has $historical" >&2
            FAIL=1
        else
            echo "[PASS] $service: $accounts accounts, historical_states == $historical (matches the metadata)"
        fi
    done < <(jq -r '.chains[] | [(.service // "?"), (.state_file // ""), ((.historical_states // "null") | tostring)] | @tsv' "$STATE_METADATA")

    # The loop is fed by process substitution, so a jq error mid-stream would
    # silently truncate it rather than fail the script.
    if [ "$SEEN_CHAINS" -ne "$CHAIN_COUNT" ]; then
        echo "[FAIL] only $SEEN_CHAINS of $CHAIN_COUNT chains could be read from .chains[]" >&2
        FAIL=1
    fi
fi

echo "=================================================================="

if [ "$FAIL" -ne 0 ]; then
    echo "GATE RESULT: FAIL -- refusing to publish this bundle" >&2
    exit 1
fi

echo "GATE RESULT: PASS -- bundle is settlement-free, has the expected chains and non-zero historical state on every chain"
exit 0
