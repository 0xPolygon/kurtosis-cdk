#!/usr/bin/env bash
#
# Immutable, self-describing per-service image tags.
#
# K4 (dev-ui-ci-snapshot / snapshot-v2-aggkit-e2e plan): every published
# snapshot image now carries a tag of the form
#   <component-version>-<unix-ts>
# e.g. kurtosis-cdk-snapshot-aggkit-001:0.11.0-rc5-1755100800
# where <component-version> is derived from the exact upstream image ref
# that produced that service's baked image (IMAGE_INFO.json's
# `base_image`, which is already params-override-aware -- see
# build-images.sh's record_image()) and <unix-ts> is ONE timestamp shared by
# every service in a single publish run.
#
# This is a pure, side-effect-free helper library: no docker/network calls.
# SINGLE SOURCE OF TRUTH for the sanitization rule -- publish-images.sh must
# not hand-roll its own version parsing.
#
# Usage:
#   source "$(dirname "$0")/lib/version-tag.sh"
#   version=$(snapshot_resolve_component_version "$base_image") || exit 1
#   tag=$(snapshot_versioned_tag "$base_image" "$unix_ts") || exit 1
#
# Every function below fails LOUDLY (non-zero return, message on stderr) on
# anything it cannot confidently resolve. There is deliberately no silent
# fallback to a placeholder like "unknown" or "latest" -- a caller that
# ignores the return code and keeps going is a bug in the caller, not this
# library papering over it.

# Idempotent source guard (see lib/ports.sh for why this matters: several
# scripts source each other and this file may be pulled in more than once).
if [ -n "${_SNAPSHOT_LIB_VERSION_TAG_SOURCED:-}" ]; then
    # shellcheck disable=SC2317 # the `exit 0` fallback only runs when this file is executed directly, not sourced
    return 0 2>/dev/null || exit 0
fi
_SNAPSHOT_LIB_VERSION_TAG_SOURCED=1

# Maximum length of the <component-version> portion of a tag, BEFORE the
# "-<unix-ts>" suffix is appended. The OCI/Docker tag grammar allows up to
# 128 characters total (https://github.com/opencontainers/distribution-spec,
# `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}`), which leaves enormous headroom even
# after reserving space for a 10-digit unix timestamp plus its separating
# dash. This cap is deliberately much tighter than that hard limit, purely
# for human readability in the GHCR package listing: the longest real
# upstream tag known today is agglayer-dev-ui's 53-character branch/commit/
# run-number ref (dispatch-feat-aggkit-backend-dd070d7db256-31574163188),
# which this cap truncates. Truncation is safe because the tag is
# informational only -- the LOAD-BEARING pin is the `@sha256:<digest>`
# recorded alongside it (see apply-digests.sh), not this string, so a
# theoretical truncation collision between two different long upstream tags
# would not weaken the pin.
SNAPSHOT_MAX_VERSION_LEN=40

# snapshot_extract_image_tag <image-ref>
# Echo the bare tag portion of a docker image reference, e.g.
#   ghcr.io/agglayer/aggkit:0.11.0-rc5   -> 0.11.0-rc5
#   haproxy:3.2-bookworm                 -> 3.2-bookworm
# Fails (non-zero, stderr message, nothing echoed) if <image-ref> is empty,
# has no explicit tag, or the only colon present belongs to a registry
# "host:port" prefix rather than a tag separator (per the standard docker
# reference grammar: a trailing ":foo" is a tag only if "foo" contains no
# "/"; a digest suffix, if present, is stripped first).
snapshot_extract_image_tag() {
    local ref="$1" no_digest after_colon
    if [ -z "$ref" ]; then
        echo "version-tag.sh: image ref is empty -- cannot resolve a version" >&2
        return 1
    fi
    no_digest="${ref%%@*}"
    after_colon="${no_digest##*:}"
    if [ "$after_colon" = "$no_digest" ]; then
        echo "version-tag.sh: image ref '$ref' has no explicit tag" >&2
        return 1
    fi
    if [ -z "$after_colon" ]; then
        echo "version-tag.sh: image ref '$ref' has an empty tag" >&2
        return 1
    fi
    case "$after_colon" in
        */*)
            echo "version-tag.sh: image ref '$ref' has no explicit tag (trailing ':...' is a registry host:port, not a tag)" >&2
            return 1
            ;;
    esac
    echo "$after_colon"
}

# snapshot_sanitize_tag_component <string>
# Sanitize <string> into something guaranteed to be a legal OCI/Docker tag
# component on its own: replace any character outside [A-Za-z0-9_.-] with
# "-", force a legal leading character (must be [A-Za-z0-9_]; OCI forbids a
# leading "." or "-"), and truncate to SNAPSHOT_MAX_VERSION_LEN. Fails if the
# input is empty or sanitizes down to nothing.
snapshot_sanitize_tag_component() {
    local raw="$1" sanitized
    if [ -z "$raw" ]; then
        echo "version-tag.sh: cannot sanitize an empty string" >&2
        return 1
    fi
    # Replace anything not alnum/underscore/dot/dash with a dash.
    sanitized=$(printf '%s' "$raw" | tr -c 'A-Za-z0-9_.-' '-')
    # OCI tags must start with [A-Za-z0-9_], not "." or "-".
    case "$sanitized" in
        [A-Za-z0-9_]*) ;;
        *) sanitized="v${sanitized}" ;;
    esac
    sanitized="${sanitized:0:$SNAPSHOT_MAX_VERSION_LEN}"
    if [ -z "$sanitized" ]; then
        echo "version-tag.sh: '$raw' sanitized down to an empty string" >&2
        return 1
    fi
    echo "$sanitized"
}

# snapshot_resolve_component_version <base_image>
# Combine snapshot_extract_image_tag + snapshot_sanitize_tag_component into
# the one call publish-images.sh needs. This is the ONLY entry point that
# should be treated as "the" version resolver -- it fails loudly (no
# "unknown" fallback) if <base_image> cannot yield a version.
snapshot_resolve_component_version() {
    local base_image="$1" tag
    tag=$(snapshot_extract_image_tag "$base_image") || return 1
    snapshot_sanitize_tag_component "$tag" || return 1
}

# snapshot_versioned_tag <base_image> <unix_ts>
# Echo "<component-version>-<unix_ts>". Fails loudly if the version cannot
# be resolved, or if <unix_ts> is not a plain non-negative integer.
snapshot_versioned_tag() {
    local base_image="$1" unix_ts="$2" version
    case "$unix_ts" in
        '' | *[!0-9]*)
            echo "version-tag.sh: unix_ts '$unix_ts' is not a non-negative integer" >&2
            return 1
            ;;
    esac
    version=$(snapshot_resolve_component_version "$base_image") || return 1
    echo "${version}-${unix_ts}"
}
