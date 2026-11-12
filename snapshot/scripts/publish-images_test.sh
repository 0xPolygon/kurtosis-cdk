#!/usr/bin/env bash
#
# Hermetic test for publish-images.sh: a fake `docker` stands in for the
# daemon and the registry, so no image is built and nothing is pushed.
#
# Asserts that the publish is ordered and all-or-nothing:
#  - every immutable tag is pushed before any alias is moved;
#  - the recorded digest is the one the push printed, and the alias points at
#    exactly that digest;
#  - an existing immutable tag, a registry that cannot tell, a missing local
#    image, a failing push or a push without a digest leave the aliases alone
#    and write no PUBLISHED_TAGS.json;
#  - --dry-run contacts no registry and records null digests.
#
# Usage: ./publish-images_test.sh   (run from anywhere)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
publish="${script_dir}/publish-images.sh"
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
registry="${work_dir}/registry"
fake_log="${work_dir}/docker.log"
mkdir -p "${fake_bin}" "${registry}"

cat > "${fake_bin}/docker" <<'FAKE'
#!/usr/bin/env bash
# Fake docker: logs every call; the "registry" is a directory of marker files.
set -euo pipefail
echo "docker $*" >> "${FAKE_LOG}"
digest_of() { printf 'sha256:%s' "$(printf '%s' "$1" | sha256sum | cut -c1-64)"; }
case "$1" in
    image)
        # docker image inspect <name>
        case " ${FAKE_MISSING_IMAGES:-} " in *" $3 "*) exit 1 ;; esac
        exit 0
        ;;
    tag)
        exit 0
        ;;
    push)
        ref="$2"
        case "${FAKE_PUSH_FAIL:-}" in
            "") ;;
            *) case "$ref" in *"${FAKE_PUSH_FAIL}"*) echo "denied" >&2; exit 1 ;; esac ;;
        esac
        repo="${ref%:*}"
        digest=$(digest_of "$repo")
        touch "${FAKE_REGISTRY}/ref-$(printf '%s' "$ref" | tr '/:@' '___')" \
            "${FAKE_REGISTRY}/digest-$(printf '%s' "${repo}@${digest}" | tr '/:@' '___')"
        echo "The push refers to repository [${repo}]"
        if [ "${FAKE_PUSH_NO_DIGEST:-}" = "1" ]; then
            echo "${ref##*:}: pushed"
        else
            echo "${ref##*:}: digest: ${digest} size: 1234"
        fi
        exit 0
        ;;
    buildx)
        shift
        case "$1" in
            version) exit 0 ;;
            imagetools)
                shift
                case "$1" in
                    inspect)
                        ref="$2"
                        if [ "${FAKE_INSPECT_ERROR:-}" = "1" ]; then echo "ERROR: unauthorized: authentication required" >&2; exit 1; fi
                        key=$(printf '%s' "$ref" | tr '/:@' '___')
                        case "$ref" in
                            *@*) [ -e "${FAKE_REGISTRY}/digest-${key}" ] && exit 0 ;;
                            *)
                                [ -e "${FAKE_REGISTRY}/ref-${key}" ] && exit 0
                                case " ${FAKE_EXISTING_TAGS:-} " in *" $ref "*) exit 0 ;; esac
                                ;;
                        esac
                        echo "ERROR: ${ref}: not found" >&2
                        exit 1
                        ;;
                    create)
                        if [ "${FAKE_CREATE_FAIL:-}" = "1" ]; then echo "ERROR: create failed" >&2; exit 1; fi
                        exit 0
                        ;;
                esac
                ;;
        esac
        ;;
esac
echo "fake docker: unsupported: $*" >&2
exit 1
FAKE
chmod +x "${fake_bin}/docker"

prefix="ghcr.io/example/snap-"
make_info() {
    local dir="${work_dir}/$1"
    mkdir -p "${dir}/images"
    cat > "${dir}/images/IMAGE_INFO.json" <<'JSON'
{
  "flavor": "anvil-aggkit",
  "images": {
    "anvil-001":   {"name": "snapshot-anvil-001:t",   "base_image": "ghcr.io/foundry-rs/foundry:v1.9.0"},
    "aggkit-001":  {"name": "snapshot-aggkit-001:t",  "base_image": "ghcr.io/agglayer/aggkit:0.11.1"},
    "agglayer":    {"name": "snapshot-agglayer:t",    "base_image": "ghcr.io/agglayer/agglayer:0.6.2"}
  }
}
JSON
    echo "${dir}/images/IMAGE_INFO.json"
}

# run_publish <name> [ENV=value ...] -- <publish args...>; sets $rc, $info, $published.
run_publish() {
    local name="$1"
    shift
    local -a envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    info=$(make_info "${name}")
    published="$(dirname "${info}")/PUBLISHED_TAGS.json"
    : > "${fake_log}"
    rc=0
    env "${envs[@]}" FAKE_LOG="${fake_log}" FAKE_REGISTRY="${registry}" PATH="${fake_bin}:${PATH}" \
        "${publish}" --unix-ts 1755100800 --source-id 1a2b3c4-r9.1 --registry-prefix "${prefix}" "$@" "${info}" \
        > "${work_dir}/${name}.out" 2>&1 || rc=$?
}

count_calls() { grep -cE "$1" "${fake_log}" || true; }

assert_rc() {
    local name="$1" want="$2"
    if { [ "${want}" = "0" ] && [ "${rc}" -eq 0 ]; } || { [ "${want}" != "0" ] && [ "${rc}" -ne 0 ]; }; then
        ok "${name}: exit status ${rc} as expected"
    else
        fail "${name}: exit status ${rc}, expected ${want} -- output:"
        cat "${work_dir}/${name}.out" >&2
    fi
}

assert_untouched() {
    local name="$1"
    if [ "$(count_calls 'imagetools create')" -eq 0 ]; then
        ok "${name}: no alias was moved"
    else
        fail "${name}: an alias was moved"
        cat "${fake_log}" >&2
    fi
    if [ -e "${published}" ]; then
        fail "${name}: PUBLISHED_TAGS.json exists although the run failed"
    else
        ok "${name}: no PUBLISHED_TAGS.json"
    fi
}

assert_no_push() {
    local name="$1"
    if [ "$(count_calls '^docker push')" -eq 0 ]; then
        ok "${name}: nothing was pushed"
    else
        fail "${name}: something was pushed"
        cat "${fake_log}" >&2
    fi
}

# ---- success: ordering, digests, aliases -------------------------------------
run_publish ok -- --tag snapshot-latest-devui
assert_rc ok 0
immutable_prefix="v1.9.0-20250813160000-1a2b3c4-r9.1"
if [ "$(count_calls '^docker push')" -eq 3 ] && [ "$(count_calls 'imagetools create')" -eq 3 ]; then
    ok "ok: three immutable pushes and three alias moves"
else
    fail "ok: unexpected number of pushes/alias moves"; cat "${fake_log}" >&2
fi
last_push=$(grep -n '^docker push' "${fake_log}" | tail -1 | cut -d: -f1)
first_create=$(grep -n 'imagetools create' "${fake_log}" | head -1 | cut -d: -f1)
if [ "${last_push}" -lt "${first_create}" ]; then
    ok "ok: every push comes before the first alias move"
else
    fail "ok: an alias was moved before the last push (push line ${last_push}, create line ${first_create})"
fi
if grep -q "docker push ${prefix}anvil-001:${immutable_prefix}\$" "${fake_log}"; then
    ok "ok: anvil-001 is pushed as ${immutable_prefix}"
else
    fail "ok: expected push of ${prefix}anvil-001:${immutable_prefix}"; cat "${fake_log}" >&2
fi
for svc in anvil-001 aggkit-001 agglayer; do
    want=$(printf 'sha256:%s' "$(printf '%s' "${prefix}${svc}" | sha256sum | cut -c1-64)")
    got=$(jq -r --arg s "${svc}" '.[$s].digest' "${published}")
    if [ "${got}" = "${want}" ]; then
        ok "ok: ${svc}: PUBLISHED_TAGS.json records the digest the push printed"
    else
        fail "ok: ${svc}: recorded digest '${got}', the push printed '${want}'"
    fi
    if grep -q "imagetools create -t ${prefix}${svc}:snapshot-latest-devui ${prefix}${svc}@${want}\$" "${fake_log}"; then
        ok "ok: ${svc}: the alias points at the pushed digest"
    else
        fail "ok: ${svc}: alias is not created from ${prefix}${svc}@${want}"; cat "${fake_log}" >&2
    fi
done
if jq -e --arg p "${prefix}" 'to_entries | all(.[]; .value.repo == ($p + .key) and (.value.tag | test("^[A-Za-z0-9_][A-Za-z0-9._-]*-20250813160000-1a2b3c4-r9\\.1$")) and .value.aliases == ["snapshot-latest-devui"])' "${published}" > /dev/null; then
    ok "ok: PUBLISHED_TAGS.json records repo, tag and aliases for every service"
else
    fail "ok: PUBLISHED_TAGS.json has an unexpected shape:"; cat "${published}" >&2
fi

# ---- the same tag a second time is refused ---------------------------------
run_publish again -- --tag snapshot-latest-devui
assert_rc again 1
assert_no_push again
assert_untouched again
if grep -q 'already exists in the registry' "${work_dir}/again.out"; then
    ok "again: the log says the immutable tag already exists"
else
    fail "again: no 'already exists' message"; cat "${work_dir}/again.out" >&2
fi

# ---- pre-flight failures ----------------------------------------------------
rm -f "${registry}"/*
run_publish existing "FAKE_EXISTING_TAGS=${prefix}agglayer:0.6.2-20250813160000-1a2b3c4-r9.1" -- --tag snapshot-latest-devui
assert_rc existing 1
assert_no_push existing
assert_untouched existing

run_publish unknown FAKE_INSPECT_ERROR=1 -- --tag snapshot-latest-devui
assert_rc unknown 1
assert_no_push unknown
assert_untouched unknown

run_publish missing-image "FAKE_MISSING_IMAGES=snapshot-agglayer:t" -- --tag snapshot-latest-devui
assert_rc missing-image 1
assert_no_push missing-image
assert_untouched missing-image

# ---- push failures -----------------------------------------------------------
rm -f "${registry}"/*
run_publish push-fails "FAKE_PUSH_FAIL=aggkit-001" -- --tag snapshot-latest-devui
assert_rc push-fails 1
assert_untouched push-fails

rm -f "${registry}"/*
run_publish no-digest FAKE_PUSH_NO_DIGEST=1 -- --tag snapshot-latest-devui
assert_rc no-digest 1
assert_untouched no-digest

rm -f "${registry}"/*
run_publish create-fails FAKE_CREATE_FAIL=1 -- --tag snapshot-latest-devui
assert_rc create-fails 1
if [ -e "${published}" ]; then
    fail "create-fails: PUBLISHED_TAGS.json exists although an alias move failed"
else
    ok "create-fails: no PUBLISHED_TAGS.json"
fi

# ---- a stale PUBLISHED_TAGS.json does not survive a failed run -----------------
rm -f "${registry}"/*
info=$(make_info stale)
published="$(dirname "${info}")/PUBLISHED_TAGS.json"
echo '{"stale": {}}' > "${published}"
rc=0
env FAKE_LOG="${fake_log}" FAKE_REGISTRY="${registry}" FAKE_MISSING_IMAGES="snapshot-agglayer:t" PATH="${fake_bin}:${PATH}" \
    "${publish}" --unix-ts 1755100800 --source-id 1a2b3c4-r9.1 --registry-prefix "${prefix}" --tag snapshot-latest-devui "${info}" > /dev/null 2>&1 || rc=$?
if [ "${rc}" -ne 0 ] && [ ! -e "${published}" ]; then
    ok "stale: a failed run removes the stale PUBLISHED_TAGS.json"
else
    fail "stale: rc ${rc}, PUBLISHED_TAGS.json exists: $([ -e "${published}" ] && echo yes || echo no)"
fi

# ---- dry run ---------------------------------------------------------------
rm -f "${registry}"/*
run_publish dry -- --dry-run --tag snapshot-latest-devui
assert_rc dry 0
if [ "$(count_calls '^docker push')" -eq 0 ] && [ "$(count_calls 'imagetools')" -eq 0 ]; then
    ok "dry: no push and no registry access"
else
    fail "dry: the dry run touched the registry"; cat "${fake_log}" >&2
fi
if jq -e 'to_entries | length == 3 and all(.[]; .value.digest == null)' "${published}" > /dev/null; then
    ok "dry: PUBLISHED_TAGS.json records null digests"
else
    fail "dry: unexpected PUBLISHED_TAGS.json"; cat "${published}" >&2
fi

# ---- argument checks ---------------------------------------------------------
rc=0
"${publish}" --registry-prefix "${prefix}" --tag > /dev/null 2>&1 || rc=$?
if [ "${rc}" -ne 0 ]; then ok "args: --tag without a value is refused"; else fail "args: --tag without a value was accepted"; fi
run_publish badtag -- --tag "bad tag"
assert_rc badtag 1
assert_no_push badtag

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "publish-images_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "publish-images_test.sh: all assertions passed"
