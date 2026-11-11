#!/usr/bin/env bash
#
# Immutable, self-describing per-service image tags.
#
# Every published snapshot image carries a tag of the form
#   <component-version>-<UTC yyyymmddHHMMSS>-<source-id>
# e.g. kurtosis-cdk-snapshot-aggkit-001:0.11.1-20261110093015-1a2b3c4-r1234567.1
# where
#   <component-version> is derived from the exact upstream image ref that
#     produced that service's baked image (IMAGE_INFO.json's `base_image`,
#     which is already params-override-aware -- see build-images.sh's
#     record_image());
#   <UTC timestamp> is ONE timestamp shared by every service of a publish run;
#   <source-id> says where the images came from and makes the tag unique per
#     run: "<short git sha>-r<run id>.<run attempt>" in GitHub Actions
#     (GITHUB_SHA, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT), "<short git sha>-l<6 hex
#     random>" for a local run. Two publishes therefore never share a tag, even
#     within the same second, and a tag can be traced back to its run.
# publish-images.sh additionally refuses to push a tag that already exists in
# the registry.
#
# This is a pure, side-effect-free helper library: no docker/network calls.
# SINGLE SOURCE OF TRUTH for the sanitization rule -- publish-images.sh must
# not hand-roll its own version parsing.
#
# Usage:
#   source "$(dirname "$0")/lib/version-tag.sh"
#   version=$(snapshot_resolve_component_version "$base_image") || exit 1
#   source_id=$(snapshot_source_id) || exit 1
#   tag=$(snapshot_versioned_tag "$base_image" "$unix_ts" "$source_id") || exit 1
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
# timestamp and source id are appended. The OCI/Docker tag grammar allows up
# to 128 characters total (https://github.com/opencontainers/distribution-spec,
# `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}`); a 40-character version, 14-digit
# timestamp and a source id of at most 40 characters stay well below that.
# The cap is purely for readability in the GHCR package listing: some
# upstream tags (branch-, commit- or run-number-derived refs) run well past
# it, and this cap truncates them. Truncation is safe because the tag is
# informational only -- the LOAD-BEARING pin is the `@sha256:<digest>`
# recorded alongside it (see apply-digests.sh), and the timestamp and source
# id keep two truncated tags apart.
SNAPSHOT_MAX_VERSION_LEN=40

# snapshot_extract_image_tag <image-ref>
# Echo the bare tag portion of a docker image reference, e.g.
#   ghcr.io/agglayer/aggkit:0.11.1       -> 0.11.1
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

# snapshot_utc_stamp <unix_ts>
# Echo the UTC time of <unix_ts> as yyyymmddHHMMSS (GNU or BSD date).
snapshot_utc_stamp() {
    local unix_ts="$1"
    case "$unix_ts" in
        '' | *[!0-9]*)
            echo "version-tag.sh: unix_ts '$unix_ts' is not a non-negative integer" >&2
            return 1
            ;;
    esac
    date -u -d "@${unix_ts}" +%Y%m%d%H%M%S 2> /dev/null \
        || date -u -r "${unix_ts}" +%Y%m%d%H%M%S 2> /dev/null \
        || {
            echo "version-tag.sh: could not format unix_ts '$unix_ts' with date" >&2
            return 1
        }
}

# snapshot_source_id
# Echo the source id of the current run (see the header). Uses
# GITHUB_SHA/GITHUB_RUN_ID/GITHUB_RUN_ATTEMPT when GITHUB_RUN_ID is set,
# otherwise `git rev-parse` of the checkout this file lives in plus a random
# suffix. Fails when the commit cannot be determined.
snapshot_source_id() {
    local sha run_id attempt rand
    run_id="${GITHUB_RUN_ID:-}"
    if [ -n "$run_id" ]; then
        sha="${GITHUB_SHA:-}"
        attempt="${GITHUB_RUN_ATTEMPT:-}"
        case "$run_id" in *[!0-9]*)
            echo "version-tag.sh: GITHUB_RUN_ID '$run_id' is not numeric" >&2
            return 1
            ;;
        esac
        case "$attempt" in '' | *[!0-9]*)
            echo "version-tag.sh: GITHUB_RUN_ATTEMPT '$attempt' is not numeric" >&2
            return 1
            ;;
        esac
        case "$sha" in '' | *[!0-9a-fA-F]*)
            echo "version-tag.sh: GITHUB_SHA '$sha' is not a commit id" >&2
            return 1
            ;;
        esac
        echo "$(printf '%s' "${sha:0:7}" | tr 'A-F' 'a-f')-r${run_id}.${attempt}"
        return 0
    fi
    sha=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --short=7 HEAD 2> /dev/null) || sha=""
    if [ -z "$sha" ]; then
        echo "version-tag.sh: cannot determine the git commit for the source id (not in a git checkout and GITHUB_RUN_ID unset)" >&2
        return 1
    fi
    rand=$(od -An -N3 -tx1 /dev/urandom 2> /dev/null | tr -d ' \n')
    if [ -z "$rand" ]; then
        rand=$(printf '%06x' $((RANDOM * 32768 + RANDOM)) | tail -c 6)
    fi
    echo "${sha}-l${rand}"
}

# snapshot_versioned_tag <base_image> <unix_ts> <source_id>
# Echo "<component-version>-<yyyymmddHHMMSS of unix_ts>-<source_id>". Fails
# loudly if the version cannot be resolved, if <unix_ts> is not a plain
# non-negative integer, or if <source_id> is empty or not a legal tag
# fragment.
snapshot_versioned_tag() {
    local base_image="$1" unix_ts="$2" source_id="${3:-}" version stamp
    stamp=$(snapshot_utc_stamp "$unix_ts") || return 1
    if [ -z "$source_id" ] || [ "${#source_id}" -gt 40 ] || [[ ! "$source_id" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
        echo "version-tag.sh: source_id '$source_id' is empty, longer than 40 characters or not a legal tag fragment" >&2
        return 1
    fi
    version=$(snapshot_resolve_component_version "$base_image") || return 1
    echo "${version}-${stamp}-${source_id}"
}
