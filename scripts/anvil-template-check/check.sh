#!/usr/bin/env bash
#
# Regression check for the config templates the anvil L2 and the two-L2 setup
# depend on: aggkit/config.toml, agglayer/config.toml,
# zkevm-bridge-service/config.toml, the bridge-ui haproxy.cfg and the
# aggkit-proxy config.toml. Several of them branch on `sequencer_type` and
# their `{{- else }}` arms render EMPTY STRINGS (or drop the key entirely)
# whenever a stack's own branch is missing; this script keeps that failure
# class fixed.
#
# Each template is rendered with real Go text/template (render.go, strict:
# a key the fixture lacks is an error, never "<no value>") against a
# checked-in JSON fixture, then:
#   1. every address/URL key the anvil branch is responsible for is present
#      AND non-empty (catches both failure shapes: empty string, absent key);
#   2. no template action (`{{`) and no "<no value>" survived rendering;
#   3. bool-gated sections are on/off for the agglayer version they target;
#   4. the two-L2 ranges (extra agglayer rollups, aggkit-proxy networks,
#      per-chain haproxy routes) render one entry per network;
#   5. the rendered haproxy.cfg passes `haproxy -c` (needs docker; set
#      ANVIL_TEMPLATE_CHECK_SKIP_HAPROXY=1 to skip on hosts without it).
#
# Usage: ./check.sh   (run from anywhere; paths are resolved relative to this
# script's own directory; needs go and jq)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

cd "${script_dir}"

for tool in go jq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "FAIL: '${tool}' is required" >&2
    exit 1
  fi
done

fail_count=0
fail() {
  echo "FAIL: $*" >&2
  fail_count=$((fail_count + 1))
}
ok() {
  echo "OK: $*"
}

# render <template> <data fixture, absolute or relative to this dir> <out>
render() {
  local template="$1" data="$2" out="$3"
  if ! go run render.go "${repo_root}/${template}" "${data}" >"${out}" 2>"${out}.stderr"; then
    fail "rendering ${template} against ${data} failed:"
    cat "${out}.stderr" >&2
    : >"${out}"
    return 1
  fi
  return 0
}

# overlay <base fixture> <jq filter> <out fixture>: a variant of a fixture.
overlay() {
  local base="$1" filter="$2" out="$3"
  jq "${filter}" "${base}" >"${out}"
}

assert_present_nonempty() {
  # assert_present_nonempty <file> <key>
  # The key must appear as `key = "..."` (or `key = [...]`) with a non-empty
  # value at least once. Catches BOTH failure shapes: an absent key and an
  # empty value.
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

assert_no_leftovers() {
  local file="$1"
  if [ ! -s "${file}" ]; then
    fail "${file}: rendered output is missing or empty"
    return
  fi
  if grep -q '{{' "${file}"; then
    fail "${file}: unexecuted template action(s) survived rendering:"
    grep -n '{{' "${file}" >&2
    return
  fi
  if grep -q '<no value>' "${file}"; then
    fail "${file}: rendered a missing value as '<no value>':"
    grep -n '<no value>' "${file}" >&2
    return
  fi
  ok "${file}: no leftover template actions or '<no value>'"
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

# assert_section_contains <file> <section header> <line regex> <desc>
# The line must appear between the section header (an exact line) and the
# next `[` header. The header is compared literally: passing it as a regex
# would make `\[` depend on the awk implementation (gawk reduces it to a
# bracket expression and matches nothing).
assert_section_contains() {
  local file="$1" header="$2" pattern="$3" desc="$4"
  if awk -v h="${header}" -v p="${pattern}" '
      $0 == h { in_section = 1; next }
      /^\[/ { in_section = 0 }
      in_section && $0 ~ p { found = 1 }
      END { exit found ? 0 : 1 }
    ' "${file}"; then
    ok "${file}: ${desc}"
  else
    fail "${file}: expected ${desc} under ${header} (pattern: ${pattern})"
  fi
}

aggkit_out="${work_dir}/aggkit-config.toml"
agglayer_out="${work_dir}/agglayer-config.toml"
zkevmbridge_out="${work_dir}/zkevmbridge-config.toml"

render "static_files/chain/shared/aggkit/config.toml" "testdata/aggkit-config-data.json" "${aggkit_out}" || true
render "static_files/agglayer/config.toml" "testdata/agglayer-config-data.json" "${agglayer_out}" || true
render "static_files/chain/shared/zkevm-bridge-service/config.toml" "testdata/zkevmbridge-config-data.json" "${zkevmbridge_out}" || true

echo
echo "=== aggkit/config.toml ==="
assert_no_leftovers "${aggkit_out}"
assert_present_nonempty "${aggkit_out}" "L2URL"
assert_present_nonempty "${aggkit_out}" "RPCURL" # absent, not empty, when the anvil branch is missing.
assert_present_nonempty "${aggkit_out}" "OpNodeURL"
assert_present_nonempty "${aggkit_out}" "polygonZkEVMAddress"
assert_present_nonempty "${aggkit_out}" "GlobalExitRootAddr"
assert_present_nonempty "${aggkit_out}" "BridgeAddr"
assert_present_nonempty "${aggkit_out}" "GlobalExitRootL2"
assert_present_nonempty "${aggkit_out}" "SovereignRollupAddr"
# The fixture's trigger_cert_mode ("ASAP") must reach the rendered config.
assert_contains "${aggkit_out}" '^TriggerCertMode = "ASAP"$' "TriggerCertMode rendered from the trigger_cert_mode argument"
# aggkit_legacy_bridge_addr=false in the fixture -> the deprecated
# polygonBridgeAddr key must NOT render.
assert_not_contains "${aggkit_out}" '^polygonBridgeAddr = ' "deprecated polygonBridgeAddr key (aggkit_legacy_bridge_addr fixture=false)"
# The fixture lists `bridge` among the components, so the bridge REST API runs
# inside the aggkit container and no URL may point at a separate
# "aggkit-00X-bridge" service.
assert_not_contains "${aggkit_out}" 'aggkit-[0-9]{3}-bridge' "'-bridge' sidecar hostname"

echo
echo "=== agglayer/config.toml, agglayer 0.6.2 ==="
assert_no_leftovers "${agglayer_out}"
assert_contains "${agglayer_out}" '^\[full-node-rpcs\]$' "[full-node-rpcs] section present"
assert_section_contains "${agglayer_out}" '[full-node-rpcs]' '^1 = "http' "network 1 URL"
assert_section_contains "${agglayer_out}" '[proof-signers]' '^1 = "0x' "network 1 proof signer"
assert_not_contains "${agglayer_out}" '^2 = ' "a network 2 entry (the fixture declares no extra rollup)"
# From agglayer v0.6.0-rc.7 on, [outbound.rpc.settle] is ignored and the
# settlement knobs live in [settlement.pessimistic-proof-tx-config].
assert_contains "${agglayer_out}" '^\[settlement\.pessimistic-proof-tx-config\]$' "[settlement.pessimistic-proof-tx-config] section present"
assert_present_nonempty "${agglayer_out}" "confirmations" # fixture: agglayer_settle_confirmations=1.
assert_not_contains "${agglayer_out}" '^\[outbound\.' "[outbound.*] section (agglayer >= 0.6.0-rc.7 ignores it)"
# The rendered settlement-policy VALUE is PascalCase (the upstream
# SettlementPolicy enum has no kebab-case rename) even though the input arg
# is lowercase. Fixture "safe" must render "SafeBlock".
assert_contains "${agglayer_out}" '^settlement-policy = "SafeBlock"$' "settlement-policy renders PascalCase 'SafeBlock' for input 'safe'"

echo
echo "=== agglayer/config.toml, agglayer 0.6.0-rc.5 (legacy settlement) ==="
overlay testdata/agglayer-config-data.json \
  '.agglayer_version = "0.6.0-rc.5" | .agglayer_use_outbound_settle = true | .agglayer_use_settlement_config = true' \
  "${work_dir}/agglayer-rc5.json"
agglayer_rc5_out="${work_dir}/agglayer-config-rc5.toml"
render "static_files/agglayer/config.toml" "${work_dir}/agglayer-rc5.json" "${agglayer_rc5_out}" || true
assert_no_leftovers "${agglayer_rc5_out}"
assert_contains "${agglayer_rc5_out}" '^\[outbound\.rpc\.settle\]$' "[outbound.rpc.settle] kept for agglayer versions that read it"
assert_contains "${agglayer_rc5_out}" '^\[settlement\.pessimistic-proof-tx-config\]$' "[settlement.*] rendered from 0.6.0-rc.1 on"

echo
echo "=== agglayer/config.toml, agglayer 0.5.0 (no settlement section) ==="
overlay testdata/agglayer-config-data.json \
  '.agglayer_version = "0.5.0" | .agglayer_use_outbound_settle = true | .agglayer_use_settlement_config = false' \
  "${work_dir}/agglayer-050.json"
agglayer_050_out="${work_dir}/agglayer-config-050.toml"
render "static_files/agglayer/config.toml" "${work_dir}/agglayer-050.json" "${agglayer_050_out}" || true
assert_no_leftovers "${agglayer_050_out}"
assert_contains "${agglayer_050_out}" '^\[outbound\.rpc\.settle\]$' "[outbound.rpc.settle] rendered"
assert_not_contains "${agglayer_050_out}" '^\[settlement' "[settlement.*] section (rejected by agglayer < 0.6.0-rc.1)"

echo
echo "=== agglayer/config.toml, two L2s ==="
overlay testdata/agglayer-config-data.json \
  '.extra_rollups = [{"network_id": 2, "op_el_rpc_url": "http://l2-anvil-002:8545", "sequencer_address": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"}]' \
  "${work_dir}/agglayer-two-l2.json"
agglayer_two_out="${work_dir}/agglayer-config-two-l2.toml"
render "static_files/agglayer/config.toml" "${work_dir}/agglayer-two-l2.json" "${agglayer_two_out}" || true
assert_no_leftovers "${agglayer_two_out}"
assert_section_contains "${agglayer_two_out}" '[full-node-rpcs]' '^1 = "http' "network 1 URL"
assert_section_contains "${agglayer_two_out}" '[full-node-rpcs]' '^2 = "http://l2-anvil-002:8545"$' "network 2 URL"
assert_section_contains "${agglayer_two_out}" '[proof-signers]' '^1 = "0x' "network 1 proof signer"
assert_section_contains "${agglayer_two_out}" '[proof-signers]' '^2 = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"$' "network 2 proof signer"

echo
echo "=== zkevm-bridge-service/config.toml ==="
assert_no_leftovers "${zkevmbridge_out}"
assert_present_nonempty "${zkevmbridge_out}" "PolygonZkEVMAddress"
assert_present_nonempty "${zkevmbridge_out}" "L2PolygonBridgeAddresses" # absent when the anvil branch is missing.
assert_present_nonempty "${zkevmbridge_out}" "RequireSovereignChainSmcs"
assert_present_nonempty "${zkevmbridge_out}" "L2PolygonZkEVMGlobalExitRootAddresses"

echo
echo "=== aggkit-proxy config.toml, two networks ==="
proxy_out="${work_dir}/aggkit-proxy-config.toml"
render "static_files/additional_services/aggkit-proxy/config.toml" "testdata/aggkit-proxy-config-data.json" "${proxy_out}" || true
assert_no_leftovers "${proxy_out}"
assert_section_contains "${proxy_out}" '[BridgeServiceFinder.BridgeURLs]' '^1 = "http://aggkit-001:5577"$' "network 1 bridge URL"
assert_section_contains "${proxy_out}" '[BridgeServiceFinder.BridgeURLs]' '^2 = "http://aggkit-002:5577"$' "network 2 bridge URL"
assert_section_contains "${proxy_out}" '[BridgeServiceFinder.RPCURLs]' '^0 = "http' "L1 (network 0) RPC URL"
assert_section_contains "${proxy_out}" '[BridgeServiceFinder.RPCURLs]' '^2 = "http://l2-anvil-002:8545"$' "network 2 RPC URL"
assert_present_nonempty "${proxy_out}" "RollupManagerAddr"
assert_present_nonempty "${proxy_out}" "L1GlobalExitRootAddress"
assert_not_contains "${proxy_out}" '^L1GlobalExitRootAddress = "0x0{40}"' "zero L1 global exit root address"
assert_section_contains "${proxy_out}" '[Tracker.AgglayerClient.GRPC]' '^URL = "agglayer:4443"$' "agglayer gRPC URL"

echo
echo "=== bridge-ui haproxy.cfg ==="
haproxy_tmpl="static_files/additional_services/bridge-ui/haproxy.cfg"
haproxy_default_out="${work_dir}/haproxy-default.cfg"
render "${haproxy_tmpl}" "testdata/haproxy-config-data.json" "${haproxy_default_out}" || true
assert_no_leftovers "${haproxy_default_out}"
assert_contains "${haproxy_default_out}" '^    use_backend backend_bridgehubapi if url_bridgehubapi$' "bridge hub route"
assert_not_contains "${haproxy_default_out}" 'is_options|aggkitapi' "aggkit routes or the CORS preflight shortcut on the bridge_hub backend"

overlay testdata/haproxy-config-data.json \
  '.bridge_hub_api_url = ""
   | .aggkit_backends = [{"path_suffix": "", "url": "aggkit-proxy-001:8080"}]
   | .l2_rpc_backends = [{"path_suffix": "-001", "url": "l2-anvil-001:8545"}, {"path_suffix": "-002", "url": "l2-anvil-002:8545"}]' \
  "${work_dir}/haproxy-aggkit.json"
haproxy_aggkit_out="${work_dir}/haproxy-aggkit.cfg"
render "${haproxy_tmpl}" "${work_dir}/haproxy-aggkit.json" "${haproxy_aggkit_out}" || true
assert_no_leftovers "${haproxy_aggkit_out}"
assert_contains "${haproxy_aggkit_out}" '^    acl is_options method OPTIONS$' "CORS preflight shortcut on the aggkit backend"
assert_contains "${haproxy_aggkit_out}" '^    use_backend backend_aggkitapi if url_aggkitapi$' "/aggkitapi route"
assert_contains "${haproxy_aggkit_out}" '^    use_backend backend_l2rpc-001 if url_l2rpc-001$' "/l2rpc-001 route"
assert_contains "${haproxy_aggkit_out}" '^    use_backend backend_l2rpc-002 if url_l2rpc-002$' "/l2rpc-002 route"
assert_not_contains "${haproxy_aggkit_out}" 'bridgehubapi' "bridge hub route without a bridge hub API"

haproxy_image="haproxy:3.2-bookworm"
if [ "${ANVIL_TEMPLATE_CHECK_SKIP_HAPROXY:-}" = "1" ]; then
  echo "SKIP: haproxy -c (ANVIL_TEMPLATE_CHECK_SKIP_HAPROXY=1)"
elif ! command -v docker >/dev/null 2>&1; then
  fail "docker is required for 'haproxy -c' (set ANVIL_TEMPLATE_CHECK_SKIP_HAPROXY=1 to skip)"
else
  # -dr: do not fail on server hostnames that only resolve inside an enclave.
  for cfg in "${haproxy_default_out}" "${haproxy_aggkit_out}"; do
    if docker run --rm -v "${cfg}:/usr/local/etc/haproxy/haproxy.cfg:ro" "${haproxy_image}" haproxy -c -dr -f /usr/local/etc/haproxy/haproxy.cfg >"${cfg}.check" 2>&1; then
      ok "${cfg}: haproxy -c accepts the configuration"
    else
      fail "${cfg}: haproxy -c rejected the configuration:"
      cat "${cfg}.check" >&2
    fi
  done
fi

echo
if [ "${fail_count}" -gt 0 ]; then
  echo "anvil-template-check: ${fail_count} assertion(s) FAILED" >&2
  exit 1
fi
echo "anvil-template-check: all assertions passed"
