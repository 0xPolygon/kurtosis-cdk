#!/usr/bin/env bash
#
# Snapshot Soundness Gate
#
# Machine-checkable pre-publish gate for the anvil-aggkit flavor's
# state/state-metadata.json. Two independent invariants, both required for a
# restored bundle to be able to settle certificates at all:
#
#   1. settlement_free == true
#      agglayer/aggkit internal databases are never captured, so restoring
#      chain state that already contains bridge/certificate activity is
#      unsound (docs/docs/advanced/snapshot.md's existing constraint, carried
#      over to this flavor).
#
#   2. every entry in .chains[] has historical_states > 0
#      (S9b) anvil_dumpState is captured with preserve_historical_states, and
#      a dump with historical_states == 0 can only serve eth_call/eth_getCode
#      at the tip -- any component (e.g. agglayer's settlement-signer nonce
#      probe) that reads state at a pre-snapshot block then panics with
#      BlockOutOfRangeError. See plans/dev-ui-ci-snapshot/s9b-evidence/.
#
# This is deliberately a SEPARATE, explicit CI gate on top of the checks
# extract-state.sh/build-images.sh already perform at capture/bake time: this
# script re-derives its verdict from the final on-disk state-metadata.json,
# so it also catches a bundle that was produced by an older/bypassed
# snapshot.sh, copied in from elsewhere, or hand-edited.
#
# Usage: gate-snapshot-soundness.sh <state-metadata.json>
#
# Exit 0  -- both invariants hold, safe to publish.
# Exit 1  -- one or more invariants violated, or the input is missing/malformed.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <state-metadata.json>" >&2
    exit 1
fi

STATE_METADATA="$1"

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
# "missing" (caught by this script's own negative-test suite). `has(...)`
# distinguishes "key absent" from "key present and false".
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

# --- Gate 2: historical_states > 0 for every chain ----------------------
CHAIN_COUNT=$(jq -r '.chains | length' "$STATE_METADATA" 2>/dev/null || echo 0)

if [ "$CHAIN_COUNT" -eq 0 ] 2>/dev/null; then
    echo "[FAIL] .chains is empty or missing -- nothing to gate on" >&2
    FAIL=1
else
    while IFS=$'\t' read -r service historical; do
        # jq prints `null` (a literal 4-char string) for a missing key, which
        # would otherwise pass a naive numeric `-gt 0` test after coercion.
        if [ -z "$historical" ] || [ "$historical" = "null" ] || ! [[ "$historical" =~ ^-?[0-9]+$ ]]; then
            echo "[FAIL] $service: historical_states missing or non-numeric ($historical)" >&2
            FAIL=1
        elif [ "$historical" -le 0 ]; then
            echo "[FAIL] $service: historical_states == $historical (must be > 0 -- a restored anvil with zero preserved historical states cannot serve eth_call at any pre-snapshot block, so agglayer's settlement-signer nonce probe panics with BlockOutOfRangeError)" >&2
            FAIL=1
        else
            echo "[PASS] $service: historical_states == $historical"
        fi
    done < <(jq -r '.chains[] | [.service, (.historical_states // "null")] | @tsv' "$STATE_METADATA")
fi

echo "=================================================================="

if [ "$FAIL" -ne 0 ]; then
    echo "GATE RESULT: FAIL -- refusing to publish this bundle" >&2
    exit 1
fi

echo "GATE RESULT: PASS -- bundle is settlement-free with non-zero historical state on every chain"
exit 0
