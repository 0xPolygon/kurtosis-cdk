#!/usr/bin/env bash
#
# K4 (snapshot-v2-aggkit-e2e plan): shell unit test for lib/version-tag.sh,
# the single source of truth for turning a service's upstream `base_image`
# ref into the immutable, self-describing tag component published to GHCR.
# Real inputs are taken straight from a captured IMAGE_INFO.json (see
# plans/snapshot-v2-aggkit-e2e/K4-evidence/) so this test exercises the exact
# strings the pipeline actually produces, not idealized examples.
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

# --- snapshot_extract_image_tag: real base_image values captured in
# K1-evidence's IMAGE_INFO.json (all 9 post-merge services) ---
assert_eq "anvil tag" "$(snapshot_extract_image_tag 'ghcr.io/foundry-rs/foundry:v1.5.1')" "v1.5.1"
assert_eq "aggkit tag" "$(snapshot_extract_image_tag 'ghcr.io/agglayer/aggkit:0.11.0-rc5')" "0.11.0-rc5"
assert_eq "agglayer tag (no v prefix, post-K3)" "$(snapshot_extract_image_tag 'ghcr.io/agglayer/agglayer:0.6.0-rc.8')" "0.6.0-rc.8"
assert_eq "haproxy tag (no registry host at all)" "$(snapshot_extract_image_tag 'haproxy:3.2-bookworm')" "3.2-bookworm"
assert_eq "dev-ui long non-semver tag" \
    "$(snapshot_extract_image_tag 'ghcr.io/agglayer/agglayer-dev-ui:dispatch-feat-aggkit-backend-dd070d7db256-31574163188')" \
    "dispatch-feat-aggkit-backend-dd070d7db256-31574163188"

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
assert_eq "already-legal string passes through unchanged" "$(snapshot_sanitize_tag_component '0.11.0-rc5')" "0.11.0-rc5"
assert_eq "disallowed chars (/ and :) become dashes" "$(snapshot_sanitize_tag_component 'foo/bar:baz')" "foo-bar-baz"
assert_eq "illegal leading char gets a 'v' prefix instead of being dropped" "$(snapshot_sanitize_tag_component '.1.2.3')" "v.1.2.3"
assert_fails "empty string rejected" snapshot_sanitize_tag_component ""

# --- length cap: the one real-world case designed to exercise it (53 chars,
# well within the OCI 128-char hard limit but over our readability cap) ---
long_devui_tag="dispatch-feat-aggkit-backend-dd070d7db256-31574163188"
assert_eq "long tag length before cap" "${#long_devui_tag}" "53"
capped=$(snapshot_sanitize_tag_component "$long_devui_tag")
assert_eq "long tag truncated to SNAPSHOT_MAX_VERSION_LEN" "${#capped}" "${SNAPSHOT_MAX_VERSION_LEN}"
assert_eq "truncation keeps the prefix (deterministic, not random)" "$capped" "${long_devui_tag:0:$SNAPSHOT_MAX_VERSION_LEN}"

# --- snapshot_resolve_component_version: the one entry point publish-images.sh uses ---
assert_eq "resolve: anvil" "$(snapshot_resolve_component_version 'ghcr.io/foundry-rs/foundry:v1.5.1')" "v1.5.1"
assert_eq "resolve: aggkit" "$(snapshot_resolve_component_version 'ghcr.io/agglayer/aggkit:0.11.0-rc5')" "0.11.0-rc5"
assert_eq "resolve: agglayer" "$(snapshot_resolve_component_version 'ghcr.io/agglayer/agglayer:0.6.0-rc.8')" "0.6.0-rc.8"
assert_eq "resolve: dev-ui (truncated)" \
    "$(snapshot_resolve_component_version 'ghcr.io/agglayer/agglayer-dev-ui:dispatch-feat-aggkit-backend-dd070d7db256-31574163188')" \
    "${long_devui_tag:0:$SNAPSHOT_MAX_VERSION_LEN}"
assert_fails "resolve: empty base_image fails loudly, no 'unknown' fallback" snapshot_resolve_component_version ""
assert_fails "resolve: tagless base_image fails loudly" snapshot_resolve_component_version "ghcr.io/agglayer/agglayer"

# --- snapshot_versioned_tag: version + shared unix-ts ---
assert_eq "versioned tag: anvil" "$(snapshot_versioned_tag 'ghcr.io/foundry-rs/foundry:v1.5.1' 1755100800)" "v1.5.1-1755100800"
assert_eq "versioned tag: aggkit" "$(snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.0-rc5' 1755100800)" "0.11.0-rc5-1755100800"
assert_fails "versioned tag: non-numeric unix_ts rejected" snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.0-rc5' "not-a-number"
assert_fails "versioned tag: empty unix_ts rejected" snapshot_versioned_tag 'ghcr.io/agglayer/aggkit:0.11.0-rc5' ""
assert_fails "versioned tag: unresolvable version still fails even with a valid ts" snapshot_versioned_tag "" 1755100800

# --- Idempotent source guard ---
# (No leftover /tmp files from assert_fails: each call cleans up its own.)
# shellcheck disable=SC1090,SC1091 # script_dir is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "${script_dir}/version-tag.sh"
assert_eq "double-source is a no-op (guard held)" "${_SNAPSHOT_LIB_VERSION_TAG_SOURCED}" "1"
assert_eq "double-source: still resolves" "$(snapshot_resolve_component_version 'ghcr.io/agglayer/aggkit:0.11.0-rc5')" "0.11.0-rc5"

echo
if [ "${fail_count}" -gt 0 ]; then
    echo "version-tag_test.sh: ${fail_count} assertion(s) FAILED" >&2
    exit 1
fi
echo "version-tag_test.sh: all assertions passed"
