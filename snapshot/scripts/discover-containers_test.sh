#!/usr/bin/env bash
#
# Hermetic test for discover-containers.sh --flavor anvil-aggkit: fake
# `kurtosis`, `docker` and `curl` executables describe an enclave, so no
# daemon or enclave is needed.
#
# Asserts that
#  - the enclave is matched by its whole name ("cdk" never matches "cdk-old");
#  - a complete two-L2 enclave yields the nine expected components;
#  - a missing aggkit-proxy, haproxy or dev-ui container fails the discovery
#    with a message naming it, instead of producing a discovery.json that
#    later stages trip over.
#
# Usage: ./discover-containers_test.sh   (run from anywhere)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

fake_bin="${work_dir}/fake-bin"
mkdir -p "${fake_bin}"

# kurtosis: `enclave ls` prints the enclaves listed in FAKE_ENCLAVES (one
# "<short uuid> <name>" per line).
cat > "${fake_bin}/kurtosis" <<'FAKE'
#!/usr/bin/env bash
if [ "$1 $2" = "enclave ls" ]; then
    echo "UUID NAME STATUS CREATION TIME"
    while read -r uuid name; do
        [ -n "$name" ] && echo "$uuid $name RUNNING 2026-01-01"
    done <<< "${FAKE_ENCLAVES}"
    exit 0
fi
echo "fake kurtosis: unsupported: $*" >&2
exit 1
FAKE

# docker: the containers of the enclave are FAKE_CONTAINERS (space separated
# names). Every inspected container publishes 8545 on host port 19000.
cat > "${fake_bin}/docker" <<'FAKE'
#!/usr/bin/env bash
args="$*"
case "$args" in
    "ps -q") echo "c1" ;;
    "inspect c1 --format "*) echo "aaa111full-uuid" ;;
    "ps -a --filter "*) for n in ${FAKE_CONTAINERS}; do echo "$n"; done ;;
    "inspect --format={{.Id}} "*) echo "id-${args##* }" ;;
    "inspect --format={{.Config.Image}} "*) echo "example/image:1" ;;
    "inspect --format={{.State.Status}} "*) echo "running" ;;
    "inspect --format={{json .Config.Cmd}} "*) echo '["anvil --port 8545"]' ;;
    "inspect --format={{json .Config.Entrypoint}} "*) echo "null" ;;
    "inspect --format {{json .NetworkSettings.Ports}} "*) echo '{"8545/tcp":[{"HostIp":"0.0.0.0","HostPort":"19000"}]}' ;;
    "inspect "*"--format={{range"*) echo "kt-net" ;;
    "port "*) echo "0.0.0.0:19000" ;;
    *) echo "fake docker: unsupported: $args" >&2; exit 1 ;;
esac
FAKE
cat > "${fake_bin}/curl" <<'FAKE'
#!/usr/bin/env bash
printf '{"jsonrpc":"2.0","id":1,"result":"0x4f2a"}'
FAKE
chmod +x "${fake_bin}"/*

full="anvil-001--abc l2-anvil-001--abc l2-anvil-002--abc aggkit-001--abc aggkit-002--abc agglayer--abc aggkit-proxy-001--abc agglayer-dev-ui-proxy-002--abc agglayer-dev-ui-002--abc"

# run_discover <name> <enclaves> <containers> [enclave arg]; sets $rc, $out_json, $log
run_discover() {
    local name="$1" enclaves="$2" containers="$3" enclave="${4:-cdk}"
    out_json="${work_dir}/${name}.json"
    log="${work_dir}/${name}.log"
    rc=0
    FAKE_ENCLAVES="${enclaves}" FAKE_CONTAINERS="${containers}" PATH="${fake_bin}:${PATH}" \
        "${script_dir}/discover-containers.sh" --flavor anvil-aggkit "${enclave}" "${out_json}" > "${log}" 2>&1 || rc=$?
}

run_discover complete "aaa111 cdk" "${full}"
if [ "${rc}" -eq 0 ] && jq -e '.components | length == 9 and (unique | length == 9)' "${out_json}" > /dev/null; then
    ok "complete: nine distinct components discovered"
else
    fail "complete: rc ${rc}"; cat "${log}" >&2
fi

run_discover similar-name-only "bbb222 cdk-old" "${full}"
if [ "${rc}" -ne 0 ] && grep -q "Enclave 'cdk' not found" "${log}"; then
    ok "similar-name-only: enclave 'cdk' is not matched by 'cdk-old'"
else
    fail "similar-name-only: rc ${rc}"; cat "${log}" >&2
fi

run_discover similar-name-first $'bbb222 cdk-old\naaa111 cdk' "${full}"
if [ "${rc}" -eq 0 ] && grep -q 'Enclave UUID (short): aaa111$' "${log}"; then
    ok "similar-name-first: the UUID of the exactly named enclave is used"
else
    fail "similar-name-first: rc ${rc}"; cat "${log}" >&2
fi

without() {
    local drop="$1" kept=""
    for n in ${full}; do
        case "${n}" in "${drop}"*) ;; *) kept="${kept} ${n}" ;; esac
    done
    echo "${kept}"
}
for pair in "aggkit-proxy-001:aggkit-proxy" "agglayer-dev-ui-proxy-002:haproxy" "agglayer-dev-ui-002:dev-ui"; do
    drop="${pair%%:*}"
    label="${pair##*:}"
    run_discover "missing-${label}" "aaa111 cdk" "$(without "${drop}")"
    if [ "${rc}" -ne 0 ] && grep -q "ERROR: .*${drop%-0*}.* not found" "${log}"; then
        ok "missing-${label}: discovery fails and names the component"
    else
        fail "missing-${label}: rc ${rc}"; cat "${log}" >&2
    fi
done

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "discover-containers_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "discover-containers_test.sh: all assertions passed"
