#!/usr/bin/env bash
#
# Hermetic test for apply-digests.sh. It runs the real script against small
# crafted bundles, with the real `docker compose config` (no daemon access
# needed) and a fake `docker buildx imagetools inspect` standing in for the
# registry.
#
# Asserts that the digest pins are applied to both compose files and the
# summary, and that the script refuses -- leaving every file untouched -- a
# dry-run PUBLISHED_TAGS.json, a malformed digest, a different service set
# than the one that was built, references that stay on a local tag, a
# registry prefix that does not match the recorded repositories and a digest
# that the registry does not know.
#
# Usage: ./apply-digests_test.sh   (run from anywhere; needs docker compose)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apply="${script_dir}/apply-digests.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

real_docker="$(command -v docker || true)"
if [ -z "${real_docker}" ] || ! "${real_docker}" compose version > /dev/null 2>&1; then
    echo "apply-digests_test.sh: 'docker compose' is required" >&2
    exit 1
fi

fail_count=0
fail() {
    echo "FAIL: $*" >&2
    fail_count=$((fail_count + 1))
}
ok() {
    echo "OK: $*"
}

# Fake docker: the registry answers `imagetools inspect` for the digests listed
# in FAKE_KNOWN_DIGESTS; everything else goes to the real docker.
fake_bin="${work_dir}/fake-bin"
mkdir -p "${fake_bin}"
cat > "${fake_bin}/docker" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = "buildx" ] && [ "\$2" = "imagetools" ] && [ "\$3" = "inspect" ]; then
    case " \${FAKE_KNOWN_DIGESTS:-} " in
        *" \${4#*@} "*) exit 0 ;;
    esac
    echo "ERROR: \$4: not found" >&2
    exit 1
fi
exec "${real_docker}" "\$@"
FAKE
chmod +x "${fake_bin}/docker"

d_a="sha256:$(printf 'a%.0s' {1..64})"
d_b="sha256:$(printf 'b%.0s' {1..64})"
d_c="sha256:$(printf 'c%.0s' {1..64})"
prefix="ghcr.io/example/snap-"

# make_bundle <name> [local tag]: a bundle with services a, b and the
# profile-gated c, plus a mounts variant where a and b are baked images and
# `agg` is a bare upstream image.
make_bundle() {
    local dir="${work_dir}/$1" tag="${2:-t}"
    mkdir -p "${dir}/images"
    jq -n --arg tag "${tag}" '{flavor: "anvil-aggkit", tag: $tag, image_prefix: "snapshot-",
        images: {a: {name: "snapshot-a:x"}, b: {name: "snapshot-b:x"}, c: {name: "snapshot-c:x"}}}' > "${dir}/images/IMAGE_INFO.json"
    jq -n '{images: {services: {a: {name: "snapshot-a:x"}, b: {name: "snapshot-b:x"}, c: {name: "snapshot-c:x"}}}}' > "${dir}/summary.json"
    local ref_a ref_b ref_c
    ref_a="\${SNAPSHOT_IMAGE_PREFIX:-snapshot-}a:\${SNAPSHOT_IMAGE_TAG:-${tag}}"
    ref_b="\${SNAPSHOT_IMAGE_PREFIX:-snapshot-}b:\${SNAPSHOT_IMAGE_TAG:-${tag}}"
    ref_c="\${SNAPSHOT_IMAGE_PREFIX:-snapshot-}c:\${SNAPSHOT_IMAGE_TAG:-${tag}}"
    cat > "${dir}/docker-compose.yml" <<YAML
services:
  a:
    image: ${ref_a}
  b:
    image: ${ref_b}
  c:
    profiles: ["devui"]
    image: ${ref_c}
YAML
    cat > "${dir}/docker-compose.mounts.yml" <<YAML
services:
  a:
    image: ${ref_a}
  b:
    image: ${ref_b}
  c:
    profiles: ["devui"]
    image: ${ref_c}
  agg:
    image: \${AGGKIT_IMAGE:-ghcr.io/agglayer/aggkit:0.11.1}
YAML
    jq -n --arg p "${prefix}" --arg da "${d_a}" --arg db "${d_b}" --arg dc "${d_c}" '{
        a: {repo: ($p + "a"), tag: "1.0-20261110093015-1a2b3c4-r1.1", digest: $da, aliases: ["alias"]},
        b: {repo: ($p + "b"), tag: "1.0-20261110093015-1a2b3c4-r1.1", digest: $db, aliases: ["alias"]},
        c: {repo: ($p + "c"), tag: "1.0-20261110093015-1a2b3c4-r1.1", digest: $dc, aliases: ["alias"]}}' > "${dir}/images/PUBLISHED_TAGS.json"
    echo "${dir}"
}

snapshot_files() {
    sha256sum "$1/summary.json" "$1/docker-compose.yml" "$1/docker-compose.mounts.yml"
}

# run_apply <bundle> [ENV=value ...] -- <args...>: sets $rc and $out.
run_apply() {
    local bundle="$1"
    shift
    local -a envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    out="${bundle}.out"
    rc=0
    env "${envs[@]}" PATH="${fake_bin}:${PATH}" "${apply}" "$@" "${bundle}" > "${out}" 2>&1 || rc=$?
}

expect_refusal() {
    local name="$1" bundle="$2" pattern="$3" before="$4"
    if [ "${rc}" -eq 0 ]; then
        fail "${name}: apply-digests.sh accepted the bundle"
        return
    fi
    if ! grep -qE "${pattern}" "${out}"; then
        fail "${name}: refused (rc ${rc}) but the output does not match '${pattern}':"
        cat "${out}" >&2
        return
    fi
    if [ "$(snapshot_files "${bundle}")" != "${before}" ]; then
        fail "${name}: refused but a bundle file was modified"
        return
    fi
    ok "${name}: refused (rc ${rc}), output matches '${pattern}', files untouched"
}

known="${d_a} ${d_b} ${d_c}"

# ---- happy path ---------------------------------------------------------------
b=$(make_bundle ok)
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" -- --registry-prefix "${prefix}"
if [ "${rc}" -eq 0 ]; then ok "ok: apply-digests.sh exited 0"; else fail "ok: rc ${rc}"; cat "${out}" >&2; fi
for svc in a b c; do
    var="d_${svc}"
    want="${prefix}${svc}@${!var}"
    if grep -qF "image: ${want}  # 1.0-20261110093015-1a2b3c4-r1.1" "${b}/docker-compose.yml"; then
        ok "ok: docker-compose.yml pins ${svc} to ${want}"
    else
        fail "ok: docker-compose.yml does not pin ${svc} to ${want}"; cat "${b}/docker-compose.yml" >&2
    fi
    if jq -e --arg s "${svc}" --arg d "${!var}" '.images.services[$s].digest == $d and (.images.services[$s].tag | length > 0)' "${b}/summary.json" > /dev/null; then
        ok "ok: summary.json records the tag and digest of ${svc}"
    else
        fail "ok: summary.json lacks the digest of ${svc}"
    fi
done
if grep -q 'SNAPSHOT_IMAGE_PREFIX' "${b}/docker-compose.yml" "${b}/docker-compose.mounts.yml"; then
    fail "ok: a SNAPSHOT_IMAGE_PREFIX reference is left"
else
    ok "ok: no SNAPSHOT_IMAGE_PREFIX reference is left in either compose file"
fi
# shellcheck disable=SC2016 # the literal ${...} reference is what the compose file contains
if grep -qF 'image: ${AGGKIT_IMAGE:-ghcr.io/agglayer/aggkit:0.11.1}' "${b}/docker-compose.mounts.yml" \
    && grep -qF "image: ${prefix}a@${d_a}" "${b}/docker-compose.mounts.yml"; then
    ok "ok: the mounts variant pins the baked images and keeps the bare upstream image"
else
    fail "ok: unexpected docker-compose.mounts.yml"; cat "${b}/docker-compose.mounts.yml" >&2
fi

# ---- glob characters in the local tag ----------------------------------------------
b=$(make_bundle glob 't*')
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" -- --registry-prefix "${prefix}"
if [ "${rc}" -eq 0 ] && [ "$(grep -c '@sha256:' "${b}/docker-compose.yml")" -eq 3 ] && ! grep -q 'SNAPSHOT_IMAGE' "${b}/docker-compose.yml"; then
    ok "glob: a tag containing '*' is matched literally"
else
    fail "glob: rc ${rc}"; cat "${out}" "${b}/docker-compose.yml" >&2
fi

# ---- refusals ------------------------------------------------------------------------
b=$(make_bundle dry); before=$(snapshot_files "${b}")
jq 'map_values(.digest = null)' "${b}/images/PUBLISHED_TAGS.json" > "${b}/p.json" && mv "${b}/p.json" "${b}/images/PUBLISHED_TAGS.json"
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" -- --registry-prefix "${prefix}"
expect_refusal dry-run "${b}" 'missing or malformed repo/tag/digest' "${before}"

b=$(make_bundle bad-digest); before=$(snapshot_files "${b}")
jq '.b.digest = "sha256:abc"' "${b}/images/PUBLISHED_TAGS.json" > "${b}/p.json" && mv "${b}/p.json" "${b}/images/PUBLISHED_TAGS.json"
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" -- --registry-prefix "${prefix}"
expect_refusal bad-digest "${b}" 'missing or malformed repo/tag/digest' "${before}"

b=$(make_bundle missing-service); before=$(snapshot_files "${b}")
jq 'del(.c)' "${b}/images/PUBLISHED_TAGS.json" > "${b}/p.json" && mv "${b}/p.json" "${b}/images/PUBLISHED_TAGS.json"
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" -- --registry-prefix "${prefix}"
expect_refusal missing-service "${b}" 'list different services' "${before}"

b=$(make_bundle extra-service); before=$(snapshot_files "${b}")
jq '.d = .c' "${b}/images/PUBLISHED_TAGS.json" > "${b}/p.json" && mv "${b}/p.json" "${b}/images/PUBLISHED_TAGS.json"
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" -- --registry-prefix "${prefix}"
expect_refusal extra-service "${b}" 'list different services' "${before}"

b=$(make_bundle residual)
cat >> "${b}/docker-compose.yml" <<'YAML'
  stray:
    image: ${SNAPSHOT_IMAGE_PREFIX:-snapshot-}stray:${SNAPSHOT_IMAGE_TAG:-t}
YAML
before=$(snapshot_files "${b}")
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" -- --registry-prefix "${prefix}"
expect_refusal residual "${b}" 'still references a locally built image' "${before}"

b=$(make_bundle wrong-prefix); before=$(snapshot_files "${b}")
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" -- --registry-prefix "ghcr.io/other/snap-"
expect_refusal wrong-prefix "${b}" 'does not match the repositories recorded at publish time' "${before}"

b=$(make_bundle unknown-digest); before=$(snapshot_files "${b}")
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${d_a} ${d_b}" -- --registry-prefix "${prefix}"
expect_refusal unknown-digest "${b}" 'cannot be found in the registry' "${before}"

b=$(make_bundle skip-registry-check)
run_apply "${b}" "FAKE_KNOWN_DIGESTS=" -- --registry-prefix "${prefix}" --skip-registry-check
if [ "${rc}" -eq 0 ]; then ok "skip-registry-check: accepted without registry access"; else fail "skip-registry-check: rc ${rc}"; cat "${out}" >&2; fi

b=$(make_bundle no-prefix-arg)
run_apply "${b}" "FAKE_KNOWN_DIGESTS=${known}" --
if [ "${rc}" -eq 0 ] && grep -qF "image: ${prefix}a@${d_a}" "${b}/docker-compose.yml"; then
    ok "no-prefix-arg: the repositories recorded at publish time are used"
else
    fail "no-prefix-arg: rc ${rc}"; cat "${out}" >&2
fi

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "apply-digests_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "apply-digests_test.sh: all assertions passed"
