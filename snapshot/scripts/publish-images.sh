#!/usr/bin/env bash
#
# Publish the self-contained anvil-aggkit snapshot images built by
# build-images.sh to a remote registry.
#
# Reads <OUTPUT_DIR>/images/IMAGE_INFO.json (written by build-images.sh) and,
# for every service it lists, publishes the local image
#   snapshot-<service>:<local-tag>
# as
#   <registry-prefix><service>:<immutable-tag>   (one per service)
#   <registry-prefix><service>:<tag>             (one per --tag given: the
#                                                 moving alias(es))
#
# The immutable tag is "<component-version>-<UTC timestamp>-<source id>", e.g.
# "0.11.1-20261110093015-1a2b3c4-r1234567.1" (see lib/version-tag.sh). The
# component version is resolved per service from IMAGE_INFO.json's
# `base_image`; the script fails if it cannot resolve one, there is no
# "unknown" fallback. The timestamp is computed once and shared by every
# service of the run (override with --unix-ts, mainly for tests); the source
# id is derived from the commit and the CI run (override with --source-id).
#
# The publish is ordered so that a failure never leaves the aliases pointing
# at a mix of old and new images:
#   1. pre-flight, without pushing anything: every service resolves an
#      immutable tag, every local image exists, buildx works, and none of the
#      immutable tags exists in the registry yet;
#   2. push the immutable tag of EVERY service and take the manifest digest
#      from the push itself, verifying that `<repo>@<digest>` resolves;
#   3. only when every service made it through step 2, move the alias(es) to
#      exactly those digests with `docker buildx imagetools create`;
#   4. write <dirname IMAGE_INFO_JSON>/PUBLISHED_TAGS.json as
#      {"<service>": {"repo": "<registry-prefix><service>", "tag": "...",
#       "digest": "sha256:...", "aliases": ["..."]}}
#      for apply-digests.sh. The file is not written (and a stale one is
#      removed) when anything above failed.
#
# Usage:
#   publish-images.sh [--dry-run] [--unix-ts <epoch-seconds>]
#                      [--source-id <id>]
#                      --registry-prefix <prefix> --tag <tag>
#                      [--tag <extra-tag> ...] <IMAGE_INFO_JSON>
#
# Example (what the snapshot-devui.yml workflow runs):
#   publish-images.sh \
#     --registry-prefix ghcr.io/0xpolygon/kurtosis-cdk-snapshot- \
#     --tag snapshot-latest-devui \
#     snapshot/snapshots/cdk-<ts>/images/IMAGE_INFO.json
#
# --dry-run: `docker tag` is executed for real (it is local-only), the pushes
# and alias moves are only ECHOED, the registry is not contacted and no
# digest is captured (PUBLISHED_TAGS.json gets null digests, which
# apply-digests.sh refuses).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091 # SCRIPT_DIR is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "$SCRIPT_DIR/lib/version-tag.sh"

DRY_RUN=false
REGISTRY_PREFIX=""
TAGS=()
IMAGE_INFO_JSON=""
UNIX_TS=""
SOURCE_ID=""

usage() {
    cat << 'EOF' >&2
Usage: publish-images.sh [--dry-run] [--unix-ts <epoch-seconds>] [--source-id <id>] --registry-prefix <prefix> --tag <tag> [--tag <extra-tag> ...] <IMAGE_INFO_JSON>
EOF
    exit 1
}

need_value() {
    if [ "$2" -lt 2 ] || [ -z "$3" ]; then
        echo "ERROR: option $1 requires a value" >&2
        usage
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --registry-prefix)
            need_value "$1" "$#" "${2:-}"
            REGISTRY_PREFIX="$2"
            shift 2
            ;;
        --tag)
            need_value "$1" "$#" "${2:-}"
            TAGS+=("$2")
            shift 2
            ;;
        --unix-ts)
            need_value "$1" "$#" "${2:-}"
            UNIX_TS="$2"
            shift 2
            ;;
        --source-id)
            need_value "$1" "$#" "${2:-}"
            SOURCE_ID="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            if [ -n "$IMAGE_INFO_JSON" ]; then
                echo "Unexpected extra argument: $1" >&2
                usage
            fi
            IMAGE_INFO_JSON="$1"
            shift
            ;;
    esac
done

if [ -z "$REGISTRY_PREFIX" ] || [ ${#TAGS[@]} -eq 0 ] || [ -z "$IMAGE_INFO_JSON" ]; then
    usage
fi

for TAG in "${TAGS[@]}"; do
    if [[ ! "$TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]]; then
        echo "ERROR: --tag '$TAG' is not a legal image tag" >&2
        exit 1
    fi
done

# One shared timestamp for every service in this publish run (not per-service
# -- a bundle where different services' immutable tags disagree on when "this
# run" happened would be actively misleading).
if [ -z "$UNIX_TS" ]; then
    UNIX_TS=$(date +%s)
fi
case "$UNIX_TS" in
    '' | *[!0-9]*)
        echo "ERROR: --unix-ts must be a non-negative integer, got: '$UNIX_TS'" >&2
        exit 1
        ;;
esac
if [ -z "$SOURCE_ID" ]; then
    SOURCE_ID=$(snapshot_source_id) || exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required" >&2
    exit 1
fi

if [ ! -f "$IMAGE_INFO_JSON" ]; then
    echo "ERROR: IMAGE_INFO.json not found: $IMAGE_INFO_JSON" >&2
    exit 1
fi

FLAVOR=$(jq -r '.flavor // "unknown"' "$IMAGE_INFO_JSON")
if [ "$FLAVOR" != "anvil-aggkit" ]; then
    echo "ERROR: $IMAGE_INFO_JSON has flavor '$FLAVOR', expected 'anvil-aggkit'" >&2
    echo "       (publishing the default/geth flavor to these GHCR repos is out of scope)" >&2
    exit 1
fi

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

PUBLISHED_TAGS_JSON="$(dirname "$IMAGE_INFO_JSON")/PUBLISHED_TAGS.json"
PUBLISHED_TMP="$PUBLISHED_TAGS_JSON.tmp"
trap 'rm -f "$PUBLISHED_TMP" "$PUBLISHED_TMP.new"' EXIT
# A failed run must not leave a PUBLISHED_TAGS.json that a later step could
# mistake for the result of this one.
rm -f "$PUBLISHED_TAGS_JSON" "$PUBLISHED_TMP" "$PUBLISHED_TMP.new"

log "Registry prefix: $REGISTRY_PREFIX"
log "Aliases to move (uniform, all services): ${TAGS[*]}"
log "Plus one immutable tag per service: <component-version>-$(snapshot_utc_stamp "$UNIX_TS")-${SOURCE_ID}"
log "Dry run: $DRY_RUN"
log ""

# `.images == {}` (or a malformed IMAGE_INFO.json) would give zero loop
# iterations below and a cheerful exit 0 -- a "successful publish" that pushed
# nothing. Refuse up front.
SERVICE_COUNT=$(jq -r 'if (.images | type) == "object" then (.images | length) else 0 end' "$IMAGE_INFO_JSON")
if [ -z "$SERVICE_COUNT" ] || [ "$SERVICE_COUNT" -lt 1 ]; then
    echo "ERROR: $IMAGE_INFO_JSON lists no images under .images -- nothing to publish" >&2
    exit 1
fi

mapfile -t SERVICES < <(jq -r '.images | keys[]' "$IMAGE_INFO_JSON")
if [ "${#SERVICES[@]}" -ne "$SERVICE_COUNT" ]; then
    echo "ERROR: could only read ${#SERVICES[@]} of $SERVICE_COUNT service names from $IMAGE_INFO_JSON" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Pre-flight: nothing is pushed until every check below has passed.
# ---------------------------------------------------------------------------
declare -A LOCAL_IMAGES VERSION_TAGS REPOS DIGESTS
PREFLIGHT_FAILED=0

if [ "$DRY_RUN" != true ] && ! docker buildx version > /dev/null 2>&1; then
    echo "ERROR: 'docker buildx' is required to resolve and verify manifest digests" >&2
    PREFLIGHT_FAILED=1
fi

for SVC in "${SERVICES[@]}"; do
    LOCAL_IMAGES[$SVC]=$(jq -r --arg s "$SVC" '.images[$s].name // ""' "$IMAGE_INFO_JSON")
    BASE_IMAGE=$(jq -r --arg s "$SVC" '.images[$s].base_image // ""' "$IMAGE_INFO_JSON")
    REPOS[$SVC]="${REGISTRY_PREFIX}${SVC}"

    if ! VERSION_TAGS[$SVC]=$(snapshot_versioned_tag "$BASE_IMAGE" "$UNIX_TS" "$SOURCE_ID"); then
        echo "ERROR: cannot resolve an immutable version tag for service '$SVC' (base_image: '$BASE_IMAGE') -- see above" >&2
        PREFLIGHT_FAILED=1
        continue
    fi
    log "Service $SVC: base_image='$BASE_IMAGE' -> immutable tag '${VERSION_TAGS[$SVC]}'"

    if [ -z "${LOCAL_IMAGES[$SVC]}" ] || ! docker image inspect "${LOCAL_IMAGES[$SVC]}" > /dev/null 2>&1; then
        echo "ERROR: local image not found: '${LOCAL_IMAGES[$SVC]}' (service: $SVC)" >&2
        PREFLIGHT_FAILED=1
        continue
    fi

    if [ "$DRY_RUN" != true ]; then
        REMOTE_REF="${REPOS[$SVC]}:${VERSION_TAGS[$SVC]}"
        if INSPECT_OUTPUT=$(docker buildx imagetools inspect "$REMOTE_REF" 2>&1); then
            echo "ERROR: $REMOTE_REF already exists in the registry -- immutable tags are never overwritten" >&2
            PREFLIGHT_FAILED=1
        elif ! grep -qiE 'not found|manifest unknown|name unknown' <<< "$INSPECT_OUTPUT"; then
            echo "ERROR: cannot tell whether $REMOTE_REF exists (registry answered: $(head -c 300 <<< "$INSPECT_OUTPUT"))" >&2
            PREFLIGHT_FAILED=1
        fi
    fi
done

if [ "$PREFLIGHT_FAILED" -ne 0 ]; then
    echo "ERROR: pre-flight failed; nothing was pushed and no alias was moved" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Push every immutable tag; the digest comes from the push itself.
# ---------------------------------------------------------------------------
COUNT=0
for SVC in "${SERVICES[@]}"; do
    REMOTE_IMAGE="${REPOS[$SVC]}:${VERSION_TAGS[$SVC]}"
    log "docker tag ${LOCAL_IMAGES[$SVC]} $REMOTE_IMAGE"
    docker tag "${LOCAL_IMAGES[$SVC]}" "$REMOTE_IMAGE"

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] would run: docker push $REMOTE_IMAGE"
        DIGESTS[$SVC]="null"
    else
        log "docker push $REMOTE_IMAGE"
        PUSH_OUTPUT=$(docker push "$REMOTE_IMAGE") || {
            echo "ERROR: docker push $REMOTE_IMAGE failed; no alias was moved" >&2
            exit 1
        }
        echo "$PUSH_OUTPUT"
        PUSHED_DIGEST=$(grep -oE 'digest: sha256:[0-9a-f]{64}' <<< "$PUSH_OUTPUT" | tail -1 | cut -d' ' -f2 || true)
        if [ -z "$PUSHED_DIGEST" ]; then
            echo "ERROR: pushed $REMOTE_IMAGE but the push output has no manifest digest; no alias was moved" >&2
            exit 1
        fi
        if ! docker buildx imagetools inspect "${REPOS[$SVC]}@${PUSHED_DIGEST}" > /dev/null 2>&1; then
            echo "ERROR: ${REPOS[$SVC]}@${PUSHED_DIGEST} does not resolve after the push; no alias was moved" >&2
            exit 1
        fi
        DIGESTS[$SVC]="$PUSHED_DIGEST"
        log "Digest for $SVC: $PUSHED_DIGEST"
    fi
    COUNT=$((COUNT + 1))
done

# ---------------------------------------------------------------------------
# 3. Move the aliases, now that every immutable tag is in place.
# ---------------------------------------------------------------------------
for SVC in "${SERVICES[@]}"; do
    for TAG in "${TAGS[@]}"; do
        ALIAS_IMAGE="${REPOS[$SVC]}:${TAG}"
        if [ "$DRY_RUN" = true ]; then
            log "docker tag ${LOCAL_IMAGES[$SVC]} $ALIAS_IMAGE"
            docker tag "${LOCAL_IMAGES[$SVC]}" "$ALIAS_IMAGE"
            log "[DRY-RUN] would run: docker buildx imagetools create -t $ALIAS_IMAGE ${REPOS[$SVC]}@<digest of ${VERSION_TAGS[$SVC]}>"
        else
            log "docker buildx imagetools create -t $ALIAS_IMAGE ${REPOS[$SVC]}@${DIGESTS[$SVC]}"
            if ! docker buildx imagetools create -t "$ALIAS_IMAGE" "${REPOS[$SVC]}@${DIGESTS[$SVC]}"; then
                echo "ERROR: could not move $ALIAS_IMAGE. Every immutable tag is published, but the aliases may now" >&2
                echo "       point at a mix of runs; re-run the same 'imagetools create -t <alias> <repo>@<digest>'" >&2
                echo "       commands for the remaining services (digests are in the log above)." >&2
                exit 1
            fi
        fi
        COUNT=$((COUNT + 1))
    done
done

# ---------------------------------------------------------------------------
# 4. Record the result.
# ---------------------------------------------------------------------------
echo '{}' > "$PUBLISHED_TMP"
ALIASES_JSON=$(printf '%s\n' "${TAGS[@]}" | jq -R . | jq -s .)
for SVC in "${SERVICES[@]}"; do
    if [ "${DIGESTS[$SVC]}" = "null" ]; then
        DIGEST_JSON="null"
    else
        DIGEST_JSON="\"${DIGESTS[$SVC]}\""
    fi
    jq --arg svc "$SVC" --arg repo "${REPOS[$SVC]}" --arg tag "${VERSION_TAGS[$SVC]}" \
        --argjson digest "$DIGEST_JSON" --argjson aliases "$ALIASES_JSON" \
        '. + {($svc): {repo: $repo, tag: $tag, digest: $digest, aliases: $aliases}}' \
        "$PUBLISHED_TMP" > "$PUBLISHED_TMP.new"
    mv "$PUBLISHED_TMP.new" "$PUBLISHED_TMP"
done

# One immutable tag plus the uniform tags per service.
EXPECTED_COUNT=$((SERVICE_COUNT * (${#TAGS[@]} + 1)))
if [ "$COUNT" -ne "$EXPECTED_COUNT" ]; then
    echo "ERROR: processed $COUNT tag(s), expected $EXPECTED_COUNT ($SERVICE_COUNT services x $((${#TAGS[@]} + 1)) tags)" >&2
    exit 1
fi

mv "$PUBLISHED_TMP" "$PUBLISHED_TAGS_JSON"
log ""
log "Wrote per-service published tags/digests: $PUBLISHED_TAGS_JSON"
log "Processed $COUNT tag(s) across $SERVICE_COUNT service(s)"

exit 0
