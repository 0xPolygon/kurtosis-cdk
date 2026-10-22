#!/usr/bin/env bash
#
# K7 (snapshot-v2-aggkit-e2e plan): hermetic regression test for
# extract-state.sh's `--flavor anvil-aggkit` config-tree emission (K5), the
# pipeline aggkit's own e2e env (test/e2e/envs/anvil-2chains/, built by A2 --
# not this repo) is built FROM.
#
# This test invokes the REAL extract-state.sh end to end against a crafted
# discovery.json fixture (testdata/extract-state-config-tree/discovery.json)
# whose agglayer/aggkit-00X/aggkit-proxy-001 containers are backed by
# checked-in fixture files (testdata/extract-state-config-tree/containers/),
# reached through fake `docker`/`curl` executables that shadow the real ones
# on PATH for the duration of the run -- no live enclave, no docker daemon,
# no network. haproxy/dev-ui are marked `found: false` in the fixture (the
# bonus, non-required files K5's own evidence also captured) so this test
# stays focused on aggkit-env-design.md (d)'s REQUIRED 11-file list.
#
# Asserts:
#  1. All 11 files on aggkit-env-design.md (d)'s list are present and
#     non-empty, at the paths extract-state.sh ACTUALLY EMITS -- see the
#     mapping comment at the top of the "aggkit configs" block in
#     extract-state.sh: kurtosis-cdk names directories after its OWN service
#     names (config/aggkit-00X/, config/aggkit-proxy-001/), not aggkit's own
#     e2e-env "001"/"002" convention (config/00X/aggkit-config.toml) --
#     asserting the latter here would test the wrong repo's naming and pass
#     even if K5's emission logic regressed.
#  2. Exactly 11 files total land under config/ for this fixture (no silent
#     extra/missing file -- the fixture deliberately excludes the optional
#     claimsponsor.keystore and the found:false haproxy/dev-ui files).
#  3. `TriggerCertMode = "ASAP"` is present in BOTH emitted aggkit configs
#     (aggkit-env-design.md (d1): `Auto` silently resolves to `EpochBased`
#     for a PessimisticProof aggsender).
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
# Only `docker cp <container>:<src> <dest>` is exercised by the anvil-aggkit
# flavor's config-copy blocks (agglayer/aggkit-00X/aggkit-proxy-001). Resolves
# <container> against the checked-in testdata/containers/<container>/<src>
# tree instead of a live one.
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
# Only the two anvil JSON-RPC calls capture_anvil_state makes are exercised
# here (eth_blockNumber, anvil_dumpState); the settlement-freeness probe is
# skipped by the fixture's empty agglayer.ports (no readrpc port published).
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
        # A minimal, valid anvil_dumpState payload: non-empty accounts AND
        # non-empty historical_states (S9b -- capture_anvil_state hard-fails
        # without both, by design).
        inner='{"accounts":{"0xabc":{}},"historical_states":{"0":{}}}'
        hex=$(printf '%s' "$inner" | xxd -p | tr -d '\n')
        resp="{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"0x${hex}\"}"
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

output_dir="${work_dir}/output"
log_file="${work_dir}/extract-state.log"

if PATH="${fake_bin}:${PATH}" "${script_dir}/extract-state.sh" --flavor anvil-aggkit \
    "${fixture_dir}/discovery.json" "${output_dir}" > "${log_file}" 2>&1; then
    ok "extract-state.sh --flavor anvil-aggkit ran cleanly against the fixture"
else
    fail "extract-state.sh --flavor anvil-aggkit exited non-zero against the fixture -- log:"
    cat "${log_file}" >&2
fi

# ---- 1 & 2: the exact 11-file tree, at the paths K5 actually emits --------
# (see extract-state.sh's mapping comment: kurtosis-cdk's own service names,
# NOT aggkit's "001"/"002" env convention).
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
        fail "missing required file: ${rel}"
    elif [ ! -s "$f" ]; then
        fail "required file is EMPTY: ${rel}"
    else
        ok "present and non-empty: ${rel}"
    fi
done

if [ -d "${output_dir}/config" ]; then
    actual_count=$(find "${output_dir}/config" -type f | wc -l)
    if [ "${actual_count}" -eq "${#expected_files[@]}" ]; then
        ok "exactly ${#expected_files[@]} files under config/ (no silent extra/missing file)"
    else
        fail "expected exactly ${#expected_files[@]} files under config/, found ${actual_count}:"
        find "${output_dir}/config" -type f | sort >&2
    fi
else
    fail "config/ directory was not created at all"
fi

# ---- 3: TriggerCertMode = "ASAP" in BOTH emitted aggkit configs -----------
for svc in aggkit-001 aggkit-002; do
    cfg="${output_dir}/config/${svc}/config.toml"
    if [ -f "$cfg" ] && grep -qF 'TriggerCertMode = "ASAP"' "$cfg"; then
        ok "${svc}/config.toml: TriggerCertMode = \"ASAP\" present"
    else
        fail "${svc}/config.toml: TriggerCertMode = \"ASAP\" NOT found (Auto silently resolves to EpochBased for a PessimisticProof aggsender -- aggkit-env-design.md (d1))"
    fi
done

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "extract-state_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "extract-state_test.sh: all assertions passed"
