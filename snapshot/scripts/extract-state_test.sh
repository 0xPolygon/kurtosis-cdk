#!/usr/bin/env bash
#
# Hermetic regression test for extract-state.sh's `--flavor anvil-aggkit`
# path: the config-tree emission, the anvil state capture, the haproxy patch
# and the settlement-freeness probe.
#
# The REAL extract-state.sh runs end to end against a crafted discovery.json
# (testdata/extract-state-config-tree/discovery.json) whose containers are
# backed by checked-in fixture files (testdata/extract-state-config-tree/
# containers/), reached through fake `docker`/`curl` executables that shadow
# the real ones on PATH -- no live enclave, no docker daemon, no network.
# The fake curl's behaviour is selected per scenario through FAKE_DUMP and
# FAKE_CERT.
#
# Scenarios:
#  base         the exact 11-file config tree lands at the paths extract-state.sh
#               emits (kurtosis-cdk service names, not aggkit's "001"/"002"
#               e2e-env convention); the state metadata describes the three
#               chains, their network ids and historical states, and records
#               the dump's own tip as the block number; the settlement probe is
#               skipped (no readrpc port) and recorded as null, not true.
#  gzip         an anvil_dumpState result that is gzip-compressed is decoded.
#  probe        with a published agglayer port and haproxy: `result: null`
#               means settlement-free, a header means it is not, and haproxy's
#               default_backend is removed while its file mode is kept.
#  probe-fail   an unreachable agglayer, an error response, an empty object or
#               a non-JSON body is NOT "no certificates": the run fails.
#  dump-fail    a dump without accounts or without historical states fails.
#
# Usage: ./extract-state_test.sh   (run from anywhere; hermetic -- the fake
# docker/curl created below are the only things named "docker"/"curl" this
# test ever invokes)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture_dir="${script_dir}/testdata/extract-state-config-tree"
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

# ---- fake docker -----------------------------------------------------------
# Only `docker cp <container>:<src> <dest>` is exercised. It resolves
# <container> against the checked-in testdata/containers/<container>/<src>
# tree instead of a live container.
fake_bin="${work_dir}/fake-bin"
mkdir -p "${fake_bin}"
cat > "${fake_bin}/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\$1" != "cp" ]; then
    echo "fake docker: unsupported subcommand '\$1'" >&2
    exit 1
fi
src="\$2"; dest="\$3"
container="\${src%%:*}"
path="\${src#*:}"
srcpath="${fixture_dir}/containers/\${container}\${path}"
if [ ! -e "\$srcpath" ]; then
    echo "fake docker cp: no fixture at \$srcpath" >&2
    exit 1
fi
mkdir -p "\$(dirname "\$dest")"
cp -a "\$srcpath" "\$dest"
EOF
chmod +x "${fake_bin}/docker"

# ---- fake curl --------------------------------------------------------------
# eth_blockNumber always answers 0xa (10). anvil_dumpState answers per
# FAKE_DUMP, with best_block_number 0xb (11) so a recorded block number of 11
# can only come from the dump itself. The agglayer certificate probe answers
# per FAKE_CERT.
cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
data="" outfile=""
args=("$@")
i=0
while [ "$i" -lt "${#args[@]}" ]; do
    case "${args[$i]}" in
        --data) data="${args[$((i + 1))]}"; i=$((i + 2)) ;;
        -o) outfile="${args[$((i + 1))]}"; i=$((i + 2)) ;;
        *) i=$((i + 1)) ;;
    esac
done

case "$data" in
    *eth_blockNumber*)
        resp='{"jsonrpc":"2.0","id":1,"result":"0xa"}'
        ;;
    *anvil_dumpState*)
        case "${FAKE_DUMP:-plain}" in
            no-accounts)     inner='{"accounts":{},"historical_states":{"0":{}},"best_block_number":"0xb"}' ;;
            no-historical)   inner='{"accounts":{"0xabc":{}},"best_block_number":"0xb"}' ;;
            *)               inner='{"accounts":{"0xabc":{}},"historical_states":{"0":{}},"best_block_number":"0xb"}' ;;
        esac
        if [ "${FAKE_DUMP:-plain}" = "gzip" ]; then
            hex=$(printf '%s' "$inner" | gzip -c | xxd -p | tr -d '\n')
        else
            hex=$(printf '%s' "$inner" | xxd -p | tr -d '\n')
        fi
        resp="{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"0x${hex}\"}"
        ;;
    *interop_getLatestKnownCertificateHeader*)
        case "${FAKE_CERT:-null}" in
            null)        resp='{"jsonrpc":"2.0","id":1,"result":null}' ;;
            cert)        resp='{"jsonrpc":"2.0","id":1,"result":{"height":0,"status":"Settled"}}' ;;
            error)       resp='{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}' ;;
            empty)       resp='{}' ;;
            garbage)     resp='<html>502 Bad Gateway</html>' ;;
            unreachable) exit 7 ;;
        esac
        ;;
    *)
        resp='{}'
        ;;
esac

if [ -n "$outfile" ]; then
    printf '%s' "$resp" > "$outfile"
else
    printf '%s' "$resp"
fi
EOF
chmod +x "${fake_bin}/curl"

# ---- discovery variants -----------------------------------------------------
base_discovery="${fixture_dir}/discovery.json"
probe_discovery="${work_dir}/discovery-probe.json"
jq '.agglayer.ports = {"4444": "19010"}
    | .haproxy = {found: true, service_name: "agglayer-dev-ui-proxy-001", container_name: "haproxy-container"}' \
    "${base_discovery}" > "${probe_discovery}"

# run_extract <name> <discovery> [VAR=value ...] -> sets $rc, $output_dir, $log_file
run_extract() {
    local name="$1" discovery="$2"
    shift 2
    output_dir="${work_dir}/${name}"
    log_file="${work_dir}/${name}.log"
    if env "$@" PATH="${fake_bin}:${PATH}" "${script_dir}/extract-state.sh" --flavor anvil-aggkit \
        "${discovery}" "${output_dir}" > "${log_file}" 2>&1; then
        rc=0
    else
        rc=$?
    fi
}

assert_success() {
    local name="$1"
    if [ "${rc}" -eq 0 ]; then
        ok "${name}: extract-state.sh exited 0"
    else
        fail "${name}: extract-state.sh exited ${rc}, expected 0 -- log:"
        cat "${log_file}" >&2
    fi
}

assert_failure() {
    local name="$1" pattern="$2"
    if [ "${rc}" -eq 0 ]; then
        fail "${name}: extract-state.sh exited 0, expected a failure"
    elif ! grep -qE "${pattern}" "${log_file}"; then
        fail "${name}: failed (rc ${rc}) but the log does not match '${pattern}' -- log:"
        cat "${log_file}" >&2
    else
        ok "${name}: failed as expected (rc ${rc}), log matches '${pattern}'"
    fi
    if [ -e "${output_dir}/state/state-metadata.json" ]; then
        fail "${name}: state-metadata.json was written although the run failed"
    else
        ok "${name}: no state-metadata.json written"
    fi
}

# assert_jq <name> <file> <jq -e filter> <description>
assert_jq() {
    local name="$1" file="$2" filter="$3" desc="$4"
    if [ ! -f "${file}" ]; then
        fail "${name}: ${desc}: ${file} does not exist"
    elif jq -e "${filter}" "${file}" > /dev/null 2>&1; then
        ok "${name}: ${desc}"
    else
        fail "${name}: ${desc} (jq: ${filter} on ${file})"
    fi
}

# ---- base: file tree and metadata -------------------------------------------
run_extract base "${base_discovery}"
assert_success base

# The exact tree, at the paths extract-state.sh emits.
expected_files=(
    "config/agglayer/config.toml"
    "config/agglayer/aggregator.keystore"
    "config/aggkit-001/config.toml"
    "config/aggkit-001/sequencer.keystore"
    "config/aggkit-001/aggoracle.keystore"
    "config/aggkit-001/sovereignadmin.keystore"
    "config/aggkit-002/config.toml"
    "config/aggkit-002/sequencer.keystore"
    "config/aggkit-002/aggoracle.keystore"
    "config/aggkit-002/sovereignadmin.keystore"
    "config/aggkit-proxy-001/config.toml"
)
for rel in "${expected_files[@]}"; do
    f="${output_dir}/${rel}"
    if [ ! -f "$f" ]; then
        fail "base: missing required file: ${rel}"
    elif [ ! -s "$f" ]; then
        fail "base: required file is EMPTY: ${rel}"
    else
        ok "base: present and non-empty: ${rel}"
    fi
done

if [ -d "${output_dir}/config" ]; then
    actual_count=$(find "${output_dir}/config" -type f | wc -l)
    if [ "${actual_count}" -eq "${#expected_files[@]}" ]; then
        ok "base: exactly ${#expected_files[@]} files under config/ (no silent extra/missing file)"
    else
        fail "base: expected exactly ${#expected_files[@]} files under config/, found ${actual_count}:"
        find "${output_dir}/config" -type f | sort >&2
    fi
else
    fail "base: config/ directory was not created at all"
fi

meta="${output_dir}/state/state-metadata.json"
assert_jq base "${meta}" '.chains | length == 3' "three chains (L1 and two L2s) in the metadata"
assert_jq base "${meta}" '[.chains[] | select(.role == "l1")] | length == 1' "one L1 chain"
assert_jq base "${meta}" '.chains | map(select(.service == "l2-anvil-001")) | .[0].network_id == 1' "l2-anvil-001 has network id 1 (read from the aggkit config)"
assert_jq base "${meta}" '.chains | map(select(.service == "l2-anvil-002")) | .[0].network_id == 2' "l2-anvil-002 has network id 2 (read from the aggkit config)"
assert_jq base "${meta}" 'all(.chains[]; .block_number == 11)' "block_number is the dump's own tip (11), not the earlier eth_blockNumber (10)"
assert_jq base "${meta}" 'all(.chains[]; .historical_states == 1)' "historical_states recomputed from every state file"
assert_jq base "${meta}" '.settlement_free == null' "settlement_free is null (not true) when the agglayer port is not published"
for svc in anvil-001 l2-anvil-001 l2-anvil-002; do
    assert_jq base "${output_dir}/state/${svc}.json" '(.accounts | length) > 0 and (.historical_states | length) > 0' "state/${svc}.json is a decoded dump"
done

# ---- gzip: compressed anvil_dumpState result --------------------------------
run_extract gzip "${base_discovery}" FAKE_DUMP=gzip
assert_success gzip
assert_jq gzip "${output_dir}/state/l2-anvil-001.json" '.accounts | length > 0' "a gzip-compressed dump is decoded to plain JSON"

# ---- dump failures ----------------------------------------------------------
run_extract no-accounts "${base_discovery}" FAKE_DUMP=no-accounts
assert_failure no-accounts 'no accounts'
run_extract no-historical "${base_discovery}" FAKE_DUMP=no-historical
assert_failure no-historical 'NO historical_states'

# ---- probe: settlement-freeness and the haproxy patch ------------------------
run_extract probe-none "${probe_discovery}" FAKE_CERT=null
assert_success probe-none
meta="${output_dir}/state/state-metadata.json"
assert_jq probe-none "${meta}" '.settlement_free == true' "'result: null' for every network is settlement-free"
assert_jq probe-none "${meta}" '.agglayer_certificates | length == 2 and all(.[]; .latest_known_certificate_height == "none")' "one 'none' certificate entry per L2"

hap="${output_dir}/config/agglayer-dev-ui-proxy-001/haproxy.cfg"
if [ ! -f "${hap}" ]; then
    fail "probe-none: haproxy.cfg was not extracted"
else
    if grep -qE 'default_backend|backend_default|agglayer-dev-ui-001' "${hap}"; then
        fail "probe-none: haproxy.cfg still references the default backend:"
        cat "${hap}" >&2
    else
        ok "probe-none: haproxy.cfg has no default_backend/backend_default"
    fi
    if grep -q '^backend backend_l1rpc$' "${hap}"; then
        ok "probe-none: haproxy.cfg keeps the other backends"
    else
        fail "probe-none: haproxy.cfg lost backend_l1rpc"
    fi
    mode=$(stat -c '%a' "${hap}")
    if [ "${mode}" = "644" ]; then
        ok "probe-none: haproxy.cfg keeps mode 644"
    else
        fail "probe-none: haproxy.cfg has mode ${mode}, expected 644"
    fi
fi

run_extract probe-cert "${probe_discovery}" FAKE_CERT=cert
assert_success probe-cert
meta="${output_dir}/state/state-metadata.json"
assert_jq probe-cert "${meta}" '.settlement_free == false' "a certificate header makes the capture not settlement-free"
assert_jq probe-cert "${meta}" 'all(.agglayer_certificates[]; .latest_known_certificate_height == "0" and .status == "Settled")' "the certificate height and status are recorded"

# ---- probe failures: "could not ask" is not "no certificates" ----------------
run_extract probe-error "${probe_discovery}" FAKE_CERT=error
assert_failure probe-error 'unusable interop_getLatestKnownCertificateHeader response'
run_extract probe-empty "${probe_discovery}" FAKE_CERT=empty
assert_failure probe-empty 'unusable interop_getLatestKnownCertificateHeader response'
run_extract probe-garbage "${probe_discovery}" FAKE_CERT=garbage
assert_failure probe-garbage 'unusable interop_getLatestKnownCertificateHeader response'
run_extract probe-unreachable "${probe_discovery}" FAKE_CERT=unreachable
assert_failure probe-unreachable 'agglayer did not answer'

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "extract-state_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "extract-state_test.sh: all assertions passed"
