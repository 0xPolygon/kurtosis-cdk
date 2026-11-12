#!/usr/bin/env bash
#
# Negative and positive cases for gate-snapshot-soundness.sh: it must accept
# a sound bundle and refuse each of the ways a bundle can be unsound or
# unreadable. Bundles are built in a temp directory; nothing outside it is
# touched.
#
# Usage: ./gate-snapshot-soundness_test.sh
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="${script_dir}/gate-snapshot-soundness.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

fail_count=0
fail() {
    echo "FAIL: $*" >&2
    fail_count=$((fail_count + 1))
}
ok() {
    echo "OK: $*"
}

good_dump='{"accounts":{"0xabc":{}},"historical_states":{"0":{},"1":{}}}'

# make_bundle <name> -> prints the bundle root; a sound two-L2 bundle.
make_bundle() {
    local root="${work_dir}/$1"
    mkdir -p "${root}/state"
    for svc in anvil-001 l2-anvil-001 l2-anvil-002; do
        printf '%s' "${good_dump}" > "${root}/state/${svc}.json"
    done
    cat > "${root}/state/state-metadata.json" <<'JSON'
{
  "flavor": "anvil-aggkit",
  "settlement_free": true,
  "agglayer_certificates": [],
  "chains": [
    {"service": "anvil-001", "role": "l1", "network_id": 0, "state_file": "state/anvil-001.json", "historical_states": 2},
    {"service": "l2-anvil-001", "role": "l2", "prefix": "001", "network_id": 1, "state_file": "state/l2-anvil-001.json", "historical_states": 2},
    {"service": "l2-anvil-002", "role": "l2", "prefix": "002", "network_id": 2, "state_file": "state/l2-anvil-002.json", "historical_states": 2}
  ]
}
JSON
    echo "${root}"
}

# edit_meta <bundle root> <jq filter>
edit_meta() {
    local meta="$1/state/state-metadata.json"
    jq "$2" "${meta}" > "${meta}.new"
    mv "${meta}.new" "${meta}"
}

# expect <name> <pass|fail> <bundle root> [gate args...]
expect() {
    local name="$1" want="$2" root="$3"
    shift 3
    local rc=0
    "${gate}" "$@" "${root}/state/state-metadata.json" > "${work_dir}/out.log" 2>&1 || rc=$?
    if [ "${want}" = "pass" ] && [ "${rc}" -eq 0 ]; then
        ok "${name}: accepted"
    elif [ "${want}" = "fail" ] && [ "${rc}" -ne 0 ]; then
        ok "${name}: refused (rc ${rc})"
    else
        fail "${name}: expected ${want}, gate exited ${rc} -- output:"
        cat "${work_dir}/out.log" >&2
    fi
}

b=$(make_bundle sound)
expect "sound bundle" pass "${b}"
expect "sound bundle, --expect-l2 2" pass "${b}" --expect-l2 2
expect "sound bundle, --expect-l2 3" fail "${b}" --expect-l2 3

b=$(make_bundle not-settlement-free); edit_meta "${b}" '.settlement_free = false'
expect "settlement_free false" fail "${b}"
b=$(make_bundle settlement-null); edit_meta "${b}" '.settlement_free = null'
expect "settlement_free null (not checked)" fail "${b}"
b=$(make_bundle settlement-missing); edit_meta "${b}" 'del(.settlement_free)'
expect "settlement_free missing" fail "${b}"

b=$(make_bundle chains-object); edit_meta "${b}" '.chains = {"a": 1}'
expect "chains is an object" fail "${b}"
b=$(make_bundle chains-number); edit_meta "${b}" '.chains = 5'
expect "chains is a number" fail "${b}"
b=$(make_bundle chains-empty); edit_meta "${b}" '.chains = []'
expect "chains empty" fail "${b}"

b=$(make_bundle one-chain); edit_meta "${b}" '.chains = [.chains[1]]'
expect "a single chain with historical states" fail "${b}"
b=$(make_bundle no-l1); edit_meta "${b}" '.chains |= map(select(.role != "l1"))'
expect "L1 missing" fail "${b}"
b=$(make_bundle no-l2); edit_meta "${b}" '.chains |= map(select(.role != "l2"))'
expect "no L2" fail "${b}"
b=$(make_bundle dup-service); edit_meta "${b}" '.chains[2].service = "l2-anvil-001"'
expect "duplicate service names" fail "${b}"
b=$(make_bundle dup-network); edit_meta "${b}" '.chains[2].network_id = 1'
expect "duplicate L2 network ids" fail "${b}"
b=$(make_bundle null-network); edit_meta "${b}" '.chains[2].network_id = null'
expect "L2 without a network id" fail "${b}"

# The metadata claims historical states that the state file does not have.
b=$(make_bundle claim-only)
printf '%s' '{"accounts":{"0xabc":{}}}' > "${b}/state/l2-anvil-002.json"
expect "metadata claims historical_states, the state file has none" fail "${b}"
b=$(make_bundle claim-mismatch)
printf '%s' '{"accounts":{"0xabc":{}},"historical_states":{"0":{}}}' > "${b}/state/l2-anvil-002.json"
expect "metadata count differs from the state file" fail "${b}"
b=$(make_bundle zero-historical)
printf '%s' '{"accounts":{"0xabc":{}},"historical_states":{}}' > "${b}/state/l2-anvil-001.json"
edit_meta "${b}" '.chains[1].historical_states = 0'
expect "historical_states 0 in both" fail "${b}"
b=$(make_bundle no-accounts)
printf '%s' '{"accounts":{},"historical_states":{"0":{}}}' > "${b}/state/anvil-001.json"
expect "state file without accounts" fail "${b}"
b=$(make_bundle missing-state); rm "${b}/state/l2-anvil-002.json"
expect "state file missing" fail "${b}"
b=$(make_bundle bad-path); edit_meta "${b}" '.chains[1].state_file = "../state/anvil-001.json"'
expect "state_file outside state/" fail "${b}"
b=$(make_bundle invalid-json); printf 'not json' > "${b}/state/state-metadata.json"
expect "metadata is not JSON" fail "${b}"

rc=0
"${gate}" "${work_dir}/does-not-exist.json" > /dev/null 2>&1 || rc=$?
if [ "${rc}" -ne 0 ]; then ok "missing metadata file: refused (rc ${rc})"; else fail "missing metadata file was accepted"; fi

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "gate-snapshot-soundness_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "gate-snapshot-soundness_test.sh: all assertions passed"
