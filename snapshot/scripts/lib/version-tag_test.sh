#!/usr/bin/env bash
#
# Shell unit test for lib/version-tag.sh, the single source of truth for
# turning a service's upstream `base_image` ref into the immutable,
# self-describing tag published to GHCR. The inputs are the base_image values
# of a real IMAGE_INFO.json, so the test exercises the strings the pipeline
# actually produces.
#
# Usage: ./version-tag_test.sh   (run from anywhere; no docker/kurtosis required)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091 # script_dir is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "${script_dir}/version-tag.sh"

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
    local desc="$1" stderr_file
    shift
    stderr_file=$(mktemp)
    if "$@" >/dev/null 2>"$stderr_file"; then
        echo "FAIL: ${desc}: expected a non-zero exit, got 0" >&2
        fail_count=$((fail_count + 1))
    else
        echo "OK: ${desc} correctly failed ($(cat "$stderr_file"))"
    fi
    rm -f "$stderr_file"
}

# --- snapshot_extract_image_tag: base_image values of a real IMAGE_INFO.json ---
assert_eq "anvil tag" "$(snapshot_extract_image_tag 'ghcr.io/foundry-rs/foundry:v1.5.1')" "v1.5.1"
assert_eq "aggkit tag" "$(snapshot_extract_image_tag 'ghcr.io/agglayer/aggkit:0.11.1')" "0.11.1"
assert_eq "agglayer tag (no v prefix)" "$(snapshot_extract_image_tag 'ghcr.io/agglayer/agglayer:0.6.2')" "0.6.2"
assert_eq "haproxy tag (no registry host at all)" "$(snapshot_extract_image_tag 'haproxy:3.2-bookworm')" "3.2-bookworm"
assert_eq "dev-ui long non-semver tag" \
    "$(snapshot_extract_image_tag 'ghcr.io/agglayer/agglayer-dev-ui:feature-aggkit-backend-branch-9f3c2a1b7d0e-31574163188')" \
    "feature-aggkit-backend-branch-9f3c2a1b7d0e-31574163188"

# --- registry:port must not be mistaken for a tag separator ---
assert_fails "registry:port with no tag is rejected, not misread as a tag" \
    snapshot_extract_image_tag "localhost:5000/foo"

# --- digest suffix is stripped before tag extraction ---
assert_eq "digest suffix stripped before tag extraction" \
    "$(snapshot_extract_image_tag 'ghcr.io/x/y:1.2.3@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')" \
    "1.2.3"

# --- empty / tagless / empty-tag refs fail loudly, never echo a fallback ---
assert_fails "empty base_image rejected" snapshot_extract_image_tag ""
assert_fails "tagless ref rejected" snapshot_extract_image_tag "ghcr.io/agglayer/agglayer"
assert_fails "empty-tag ref rejected" snapshot_extract_image_tag "ghcr.io/agglayer/agglayer:"

# --- snapshot_sanitize_tag_component ---
assert_eq "already-legal string passes through unchanged" "$(snapshot_sanitize_tag_component '0.11.1')" "0.11.1"
assert_eq "disallowed chars (/ and :) become dashes" "$(snapshot_sanitize_tag_component 'foo/bar:baz')" "foo-bar-baz"
assert_eq "illegal leading char gets a 'v' prefix instead of being dropped" "$(snapshot_sanitize_tag_component '.1.2.3')" "v.1.2.3"
assert_fails "empty string rejected" snapshot_sanitize_tag_component ""

# --- length cap: a branch/commit/run-number-derived tag (54 chars, well
# within the OCI 128-char hard limit but over our readability cap) ---
long_devui_tag="feature-aggkit-backend-branch-9f3c2a1b7d0e-31574163188"
assert_eq "long tag length before cap" "${#long_devui_tag}" "54"
capped=$(snapshot_sanitize_tag_component "$long_devui_tag")
assert_eq "long tag truncated to SNAPSHOT_MAX_VERSION_LEN" "${#capped}" "${SNAPSHOT_MAX_VERSION_LEN}"
assert_eq "truncation keeps the prefix (deterministic, not random)" "$capped" "${long_devui_tag:0:$SNAPSHOT_MAX_VERSION_LEN}"

# --- snapshot_resolve_component_version: the one entry point publish-images.sh uses ---
assert_eq "resolve: anvil" "$(snapshot_resolve_component_version 'ghcr.io/foundry-rs/foundry:v1.5.1')" "v1.5.1"
assert_eq "resolve: aggkit" "$(snapshot_resolve_component_version 'ghcr.io/agglayer/aggkit:0.11.1')" "0.11.1"
assert_eq "resolve: agglayer" "$(snapshot_resolve_component_version 'ghcr.io/agglayer/agglayer:0.6.2')" "0.6.2"
assert_eq "resolve: dev-ui (truncated)" \
    "$(snapshot_resolve_component_version 'ghcr.io/agglayer/agglayer-dev-ui:feature-aggkit-backend-branch-9f3c2a1b7d0e-31574163188')" \
    "${long_devui_tag:0:$SNAPSHOT_MAX_VERSION_LEN}"
assert_fails "resolve: empty base_image fails loudly, no 'unknown' fallback" snapshot_resolve_component_version ""
assert_fails "resolve: tagless base_image fails loudly" snapshot_resolve_component_version "ghcr.io/agglayer/agglayer"

# --- snapshot_utc_stamp ---
assert_eq "utc stamp of 1755100800" "$(snapshot_utc_stamp 1755100800)" "20250813160000"
assert_eq "utc stamp of the epoch" "$(snapshot_utc_stamp 0)" "19700101000000"
assert_fails "utc stamp: non-numeric rejected" snapshot_utc_stamp "yesterday"
assert_fails "utc stamp: empty rejected" snapshot_utc_stamp ""

# --- snapshot_source_id ---
assert_eq "source id in GitHub Actions" \
    "$(GITHUB_RUN_ID=1234567 GITHUB_RUN_ATTEMPT=2 GITHUB_SHA=1A2B3C4D5E6F7A8B9C0D snapshot_source_id)" \
    "1a2b3c4-r1234567.2"
assert_fails "source id: missing run attempt" env -u GITHUB_RUN_ATTEMPT GITHUB_RUN_ID=1 GITHUB_SHA=abcdef0123 bash -c "source '${script_dir}/version-tag.sh'; snapshot_source_id"
assert_fails "source id: non-hex sha" env GITHUB_RUN_ID=1 GITHUB_RUN_ATTEMPT=1 GITHUB_SHA=not-a-sha bash -c "source '${script_dir}/version-tag.sh'; snapshot_source_id"
local_id_a=$(bash -c "unset GITHUB_RUN_ID; source '${script_dir}/version-tag.sh'; snapshot_source_id")
local_id_b=$(bash -c "unset GITHUB_RUN_ID; source '${script_dir}/version-tag.sh'; snapshot_source_id")
case "$local_id_a" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-l[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) assert_eq "local source id has the <sha>-l<6 hex> shape" "ok" "ok" ;;
    *) assert_eq "local source id has the <sha>-l<6 hex> shape" "$local_id_a" "<sha>-l<6 hex>" ;;
esac
if [ "$local_id_a" != "$local_id_b" ]; then
    echo "OK: two local source ids differ (${local_id_a} vs ${local_id_b})"
else
    echo "FAIL: two local source ids are identical (${local_id_a})" >&2
    fail_count=$((fail_count + 1))
fi

# --- snapshot_versioned_tag: version + shared timestamp + source id ---
assert_eq "versioned tag: anvil" \
    "$(snapshot_versioned_tag 'ghcr.io/foundry-rs/foundry:v1.5.1' 1755100800 1a2b3c4-r12.1)" \
    "v1.5.1-20250813160000-1a2b3c4-r12.1"
assert_eq "versioned tag: aggkit" \
    "$(snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.1' 1755100800 1a2b3c4-r12.1)" \
    "0.11.1-20250813160000-1a2b3c4-r12.1"
# Same second, same component, different runs: the tags differ.
tag_run_a=$(snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.1' 1755100800 1a2b3c4-r12.1)
tag_run_b=$(snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.1' 1755100800 1a2b3c4-r12.2)
if [ "$tag_run_a" != "$tag_run_b" ]; then
    echo "OK: same second, different run attempt -> different tags"
else
    echo "FAIL: tags collide for two runs in the same second: $tag_run_a" >&2
    fail_count=$((fail_count + 1))
fi
# A truncated long version plus the longest allowed source id stays a legal tag.
long_tag=$(snapshot_versioned_tag 'ghcr.io/agglayer/agglayer-dev-ui:feature-aggkit-backend-branch-9f3c2a1b7d0e-31574163188' 1755100800 "1a2b3c4-r123456789012.12")
if [ "${#long_tag}" -le 128 ] && [[ "$long_tag" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
    echo "OK: longest tag is ${#long_tag} characters and a legal OCI tag"
else
    echo "FAIL: long tag is not a legal OCI tag (${#long_tag}): $long_tag" >&2
    fail_count=$((fail_count + 1))
fi
assert_fails "versioned tag: non-numeric unix_ts rejected" snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.1' "not-a-number" 1a2b3c4-r1.1
assert_fails "versioned tag: empty unix_ts rejected" snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.1' "" 1a2b3c4-r1.1
assert_fails "versioned tag: missing source id rejected" snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.1' 1755100800
assert_fails "versioned tag: illegal source id rejected" snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.1' 1755100800 "bad/id"
assert_fails "versioned tag: unresolvable version still fails even with a valid ts" snapshot_versioned_tag "" 1755100800 1a2b3c4-r1.1

# --- Idempotent source guard ---
# (No leftover /tmp files from assert_fails: each call cleans up its own.)
# shellcheck disable=SC1090,SC1091 # script_dir is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "${script_dir}/version-tag.sh"
assert_eq "double-source is a no-op (guard held)" "${_SNAPSHOT_LIB_VERSION_TAG_SOURCED}" "1"
assert_eq "double-source: still resolves" "$(snapshot_resolve_component_version 'ghcr.io/agglayer/aggkit:0.11.1')" "0.11.1"

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "version-tag_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "version-tag_test.sh: all assertions passed"
