#!/usr/bin/env bash
#
# S15 (dev-ui-ci-snapshot plan): shell unit test for lib/ports.sh, the single
# source of truth for snapshot bundle host-port numbering (see that file's
# header comment -- the port arithmetic used to be copy-pasted in three
# places, which is exactly how a compose file and its summary.json drift
# apart). This test asserts the documented contract so a change to the
# arithmetic, the offset table or the env-var naming scheme fails loudly
# here instead of silently producing a compose file that disagrees with its
# own summary.
#
# Usage: ./ports_test.sh   (run from anywhere; no kurtosis/docker required)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091 # script_dir is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "${script_dir}/ports.sh"

fail_count=0
assert_eq() {
  local desc="$1" actual="$2" expected="$3"
  if [ "${actual}" != "${expected}" ]; then
    echo "FAIL: ${desc}: got '${actual}', want '${expected}'" >&2
    fail_count=$((fail_count + 1))
  else
    echo "OK: ${desc} -> ${actual}"
  fi
}
assert_fails() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL: ${desc}: expected a non-zero exit, got 0" >&2
    fail_count=$((fail_count + 1))
  else
    echo "OK: ${desc} correctly failed"
  fi
}

# --- snapshot_l2_port: BASE + prefix*STRIDE + offset ---
assert_eq "L2 001 http port" "$(snapshot_l2_port 001 http)" "11545"
assert_eq "L2 002 http port" "$(snapshot_l2_port 002 http)" "12545"
assert_eq "L2 001 ws port" "$(snapshot_l2_port 001 ws)" "11546"
assert_eq "L2 001 aggkit_rpc port" "$(snapshot_l2_port 001 aggkit_rpc)" "11576"
assert_eq "L2 002 aggkit_rest port" "$(snapshot_l2_port 002 aggkit_rest)" "12577"

# --- snapshot_l2_port_env: <PREFIX>_<KEY upper>_PORT ---
assert_eq "L2 001 http env name" "$(snapshot_l2_port_env 001 http)" "L2_001_HTTP_PORT"
assert_eq "L2 002 aggkit_rest env name" "$(snapshot_l2_port_env 002 aggkit_rest)" "L2_002_AGGKIT_REST_PORT"

# --- snapshot_l2_port_expr: compose interpolation expr combining the two ---
# shellcheck disable=SC2016 # literal ${VAR:-default} compose-interpolation syntax, not shell expansion
assert_eq "L2 001 http expr" "$(snapshot_l2_port_expr 001 http)" '${L2_001_HTTP_PORT:-11545}'
# shellcheck disable=SC2016 # literal ${VAR:-default} compose-interpolation syntax, not shell expansion
assert_eq "L2 002 ws expr" "$(snapshot_l2_port_expr 002 ws)" '${L2_002_WS_PORT:-12546}'

# --- snapshot_fixed_port / _env / _expr ---
assert_eq "fixed devnet_proxy port" "$(snapshot_fixed_port devnet_proxy)" "8555"
assert_eq "fixed l1_rpc port" "$(snapshot_fixed_port l1_rpc)" "8545"
assert_eq "fixed devnet_proxy env name" "$(snapshot_fixed_port_env devnet_proxy)" "DEVNET_PROXY_PORT"
# shellcheck disable=SC2016 # literal ${VAR:-default} compose-interpolation syntax, not shell expansion
assert_eq "fixed devnet_proxy expr" "$(snapshot_fixed_port_expr devnet_proxy)" '${DEVNET_PROXY_PORT:-8555}'
# shellcheck disable=SC2016 # literal ${VAR:-default} compose-interpolation syntax, not shell expansion
assert_eq "fixed dev_ui expr" "$(snapshot_fixed_port_expr dev_ui)" '${DEVUI_PORT:-8557}'

# --- Historical offsets must never change (re-pointing an already-published
# bundle's documented ports silently is exactly the regression this guards
# against -- see ports.sh's header comment). ---
assert_eq "historical offset: http" "${SNAPSHOT_L2_PORT_OFFSETS[http]}" "545"
assert_eq "historical offset: ws" "${SNAPSHOT_L2_PORT_OFFSETS[ws]}" "546"
assert_eq "historical offset: engine" "${SNAPSHOT_L2_PORT_OFFSETS[engine]}" "551"
assert_eq "historical offset: node_rpc" "${SNAPSHOT_L2_PORT_OFFSETS[node_rpc]}" "547"
assert_eq "historical offset: node_metrics" "${SNAPSHOT_L2_PORT_OFFSETS[node_metrics]}" "300"
assert_eq "historical offset: aggkit_rpc" "${SNAPSHOT_L2_PORT_OFFSETS[aggkit_rpc]}" "576"
assert_eq "historical offset: aggkit_rest" "${SNAPSHOT_L2_PORT_OFFSETS[aggkit_rest]}" "577"

# --- Unknown keys must fail loudly, not silently return an empty/zero port
# (a caller that mistypes a key must not get a compose file with a blank
# port mapping). ---
assert_fails "unknown L2 port key rejected" snapshot_l2_port 001 nonexistent_key
# K1: the `-bridge` sibling service was merged into the main aggkit process,
# so its dedicated JSON-RPC offset (aggkit_bridge_rpc) was deleted rather than
# left dangling with nothing rendering it.
assert_fails "deleted aggkit_bridge_rpc key rejected" snapshot_l2_port 001 aggkit_bridge_rpc
assert_fails "unknown fixed port key rejected" snapshot_fixed_port nonexistent_key
assert_fails "unknown L2 port env key rejected" snapshot_l2_port_env 001 nonexistent_key
assert_fails "unknown fixed port env key rejected" snapshot_fixed_port_env nonexistent_key

# --- Idempotent source guard: sourcing twice must not error or reset state. ---
# shellcheck disable=SC1090,SC1091 # script_dir is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "${script_dir}/ports.sh"
assert_eq "double-source is a no-op (guard held)" "${_SNAPSHOT_LIB_PORTS_SOURCED}" "1"
assert_eq "double-source: offsets survive" "$(snapshot_l2_port 001 http)" "11545"

echo
if [ "${fail_count}" -gt 0 ]; then
  echo "ports_test.sh: ${fail_count} assertion(s) FAILED" >&2
  exit 1
fi
echo "ports_test.sh: all assertions passed"
