#!/usr/bin/env bash
#
# S15 (dev-ui-ci-snapshot plan): regression check for the anvil-L2 template
# branches added in S4/S4b -- aggkit/config.toml, agglayer/config.toml and
# zkevm-bridge-service/config.toml all branch on `sequencer_type`, and their
# `{{- else }}` fallback arms render EMPTY STRINGS (or, for RPCURL /
# L2PolygonBridgeAddresses, drop the key entirely) whenever a stack's own
# branch is missing. This is the "silent-fallback" failure class S4 found and
# fixed; this script is the regression net that keeps it fixed.
#
# It renders each template with real Go text/template (render.go) against a
# checked-in JSON fixture captured from a live sequencer_type: anvil enclave
# (see plans/dev-ui-ci-snapshot/s15-evidence/), then asserts:
#   1. every address/URL key the anvil branch is responsible for is present
#      AND non-empty (catches both failure shapes: empty string, absent key);
#   2. no template action (`{{`) survived un-executed;
#   3. bool-gated sections that should be on/off for this fixture actually
#      are (defends against the boolean-vs-string stringification pitfall
#      documented in render.go).
#
# Usage: ./check.sh   (run from anywhere; paths are resolved relative to this
# script's own directory)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

cd "${script_dir}"

fail_count=0
fail() {
  echo "FAIL: $*" >&2
  fail_count=$((fail_count + 1))
}
ok() {
  echo "OK: $*"
}

render() {
  local template="$1" data="$2" out="$3"
  if ! go run render.go "${repo_root}/${template}" "testdata/${data}" >"${out}" 2>"${out}.stderr"; then
    fail "rendering ${template} against testdata/${data} failed:"
    cat "${out}.stderr" >&2
    return 1
  fi
  return 0
}

assert_present_nonempty() {
  # assert_present_nonempty <file> <key>
  # The key must appear as `key = "..."` (or `key = [...]`) with a non-empty
  # value at least once. Catches BOTH failure shapes: absent key (T5's
  # RPCURL / L2PolygonBridgeAddresses class) and empty value (every other
  # T-item).
  local file="$1" key="$2"
  local matches
  matches=$(grep -cE "^${key} = " "${file}" || true)
  if [ "${matches}" -eq 0 ]; then
    fail "${file}: key '${key}' is entirely ABSENT (expected at least one non-empty occurrence)"
    return
  fi
  local empty
  empty=$(grep -cE "^${key} = \"\"\$|^${key} = \[\]\$" "${file}" || true)
  if [ "${empty}" -gt 0 ]; then
    fail "${file}: key '${key}' rendered EMPTY (${empty} occurrence(s))"
    return
  fi
  ok "${file}: '${key}' present and non-empty (${matches} occurrence(s))"
}

assert_no_leftover_actions() {
  local file="$1"
  if grep -q '{{' "${file}"; then
    fail "${file}: unexecuted template action(s) survived rendering:"
    grep -n '{{' "${file}" >&2
    return
  fi
  ok "${file}: no leftover template actions"
}

assert_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qE "${pattern}" "${file}"; then
    ok "${file}: ${desc}"
  else
    fail "${file}: expected ${desc} (pattern: ${pattern})"
  fi
}

assert_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qE "${pattern}" "${file}"; then
    fail "${file}: unexpected ${desc} (pattern: ${pattern})"
  else
    ok "${file}: correctly does NOT contain ${desc}"
  fi
}

aggkit_out="${work_dir}/aggkit-config.toml"
agglayer_out="${work_dir}/agglayer-config.toml"
zkevmbridge_out="${work_dir}/zkevmbridge-config.toml"

render "static_files/chain/shared/aggkit/config.toml" "aggkit-config-data.json" "${aggkit_out}"
render "static_files/agglayer/config.toml" "agglayer-config-data.json" "${agglayer_out}"
render "static_files/chain/shared/zkevm-bridge-service/config.toml" "zkevmbridge-config-data.json" "${zkevmbridge_out}"

echo
echo "=== aggkit/config.toml (S4 T2/T3/T5/T6/T7/T8/T9/T11/T12) ==="
assert_no_leftover_actions "${aggkit_out}"
assert_present_nonempty "${aggkit_out}" "L2URL"
assert_present_nonempty "${aggkit_out}" "RPCURL" # T5: used to be ABSENT, not empty.
assert_present_nonempty "${aggkit_out}" "OpNodeURL"
assert_present_nonempty "${aggkit_out}" "polygonZkEVMAddress"
assert_present_nonempty "${aggkit_out}" "GlobalExitRootAddr"
assert_present_nonempty "${aggkit_out}" "BridgeAddr"
assert_present_nonempty "${aggkit_out}" "GlobalExitRootL2"
assert_present_nonempty "${aggkit_out}" "SovereignRollupAddr"
# aggkit_autoclaim_enabled=true in the fixture -> [AutoClaim] must render.
assert_contains "${aggkit_out}" '^\[AutoClaim\]$' "[AutoClaim] section present (aggkit_autoclaim_enabled fixture=true)"
# aggkit_legacy_bridge_addr=false in the fixture -> the deprecated
# polygonBridgeAddr key must NOT render.
assert_not_contains "${aggkit_out}" '^polygonBridgeAddr = ' "deprecated polygonBridgeAddr key (aggkit_legacy_bridge_addr fixture=false)"
# K1 (aggkit merge): the bridge REST API now runs in-process inside each
# aggkit-00X container -- there is no more standalone "aggkit-00X-bridge"
# sidecar to route AutoClaim's BridgeServiceFinder at. The fixture's
# aggkit_autoclaim_bridge_urls used to carry a stale pre-merge "-bridge"
# hostname; assert it never comes back.
assert_not_contains "${aggkit_out}" 'aggkit-[0-9]{3}-bridge' "stale pre-merge '-bridge' sidecar hostname in [AutoClaim.BridgeServiceFinder.BridgeURLs] (K1 merged the bridge REST API into the main aggkit container)"

echo
echo "=== agglayer/config.toml ==="
assert_no_leftover_actions "${agglayer_out}"
assert_contains "${agglayer_out}" '^\[full-node-rpcs\]$' "[full-node-rpcs] section present"
assert_present_nonempty "${agglayer_out}" "1" # `1 = "<url>"` network-1 URL under [full-node-rpcs].
# K3 (snapshot-v2-aggkit-e2e plan): [outbound.rpc.settle] used to be the
# (dead, since agglayer PR #1393) home for settlement confirmations. K3
# migrated the live knob to [settlement.pessimistic-proof-tx-config]. A
# revert of K3 would silently restore the dead [outbound.*] section AND drop
# back to agglayer's upstream 12-confirmation default -- assert BOTH: the new
# section renders a present, non-empty confirmations value, and no
# [outbound.* section survives at all.
assert_contains "${agglayer_out}" '^\[settlement\.pessimistic-proof-tx-config\]$' "[settlement.pessimistic-proof-tx-config] section present (K3 migration target)"
assert_present_nonempty "${agglayer_out}" "confirmations" # fixture: agglayer_settle_confirmations=1.
assert_not_contains "${agglayer_out}" '^\[outbound\.' "dead [outbound.*] section (K3 migrated it away -- must never come back)"
# K3: settlement-policy's rendered VALUE is PascalCase (upstream
# SettlementPolicy enum has no #[serde(rename_all = "kebab-case")], confirmed
# against agglayer's own v0.6.0-rc.8 fixtures) even though the input arg and
# the TOML key are both lowercase/kebab-case. Fixture agglayer_settlement_policy
# is "safe" -> must render "SafeBlock", NOT "safe" or "Safe" or "safe-block".
assert_contains "${agglayer_out}" '^settlement-policy = "SafeBlock"$' "settlement-policy renders PascalCase 'SafeBlock' for input 'safe' (NOT kebab-case)"

echo
echo "=== zkevm-bridge-service/config.toml (S4 T13, the 10th branch site) ==="
assert_no_leftover_actions "${zkevmbridge_out}"
assert_present_nonempty "${zkevmbridge_out}" "PolygonZkEVMAddress"
assert_present_nonempty "${zkevmbridge_out}" "L2PolygonBridgeAddresses" # used to be ABSENT.
assert_present_nonempty "${zkevmbridge_out}" "RequireSovereignChainSmcs"
assert_present_nonempty "${zkevmbridge_out}" "L2PolygonZkEVMGlobalExitRootAddresses"

echo
if [ "${fail_count}" -gt 0 ]; then
  echo "anvil-template-check: ${fail_count} assertion(s) FAILED" >&2
  exit 1
fi
echo "anvil-template-check: all assertions passed"
