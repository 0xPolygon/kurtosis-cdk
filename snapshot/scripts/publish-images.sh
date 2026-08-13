#!/usr/bin/env bash
#
# Publish the self-contained anvil-aggkit snapshot images built by
# build-images.sh to a remote registry.
#
# Reads <OUTPUT_DIR>/images/IMAGE_INFO.json (written by build-images.sh) and,
# for every service it lists, tags the local image
#   snapshot-<service>:<local-tag>
# as
#   <registry-prefix><service>:<tag>          (for every --tag given, PLUS
#                                               one automatic per-service
#                                               "<component-version>-<unix-ts>"
#                                               tag -- see below)
# then pushes each resulting reference -- or, with --dry-run, prints the
# exact `docker tag` / `docker push` commands without running the push (tag
# is still a purely local, side-effect-free operation, so it always runs; see
# --dry-run below for the precise split).
#
# K4 (snapshot-v2-aggkit-e2e plan): in ADDITION to whatever uniform --tag
# values are given (typically just the moving `snapshot-latest-devui` human
# alias -- the old `snapshot-<sha>` pinning tag has been retired), every
# service is always also tagged+pushed with an immutable, self-describing
# tag of the form "<component-version>-<unix-ts>", e.g.
# "0.11.0-rc5-1755100800". <component-version> is resolved per-service from
# IMAGE_INFO.json's `base_image` (see lib/version-tag.sh -- this fails the
# whole script loudly if it cannot resolve a version for any service, no
# silent "unknown" fallback); <unix-ts> is ONE timestamp computed once and
# shared by every service in this run (override with --unix-ts, mainly for
# tests). On a REAL (non-dry-run) push, the resulting GHCR manifest digest is
# captured right after the push (once per service, via
# `docker buildx imagetools inspect`) and written to
# <dirname IMAGE_INFO_JSON>/PUBLISHED_TAGS.json as
# {"<service>": {"tag": "<version>-<ts>", "digest": "sha256:..."}}, for a
# later, separate step (apply-digests.sh) to patch into summary.json and
# docker-compose.yml -- this script does not touch either of those files
# itself.
#
# Usage:
#   publish-images.sh [--dry-run] [--unix-ts <epoch-seconds>]
#                      --registry-prefix <prefix> --tag <tag>
#                      [--tag <extra-tag> ...] <IMAGE_INFO_JSON>
#
# Example (what the snapshot-devui.yml workflow runs):
#   publish-images.sh \
#     --registry-prefix ghcr.io/0xpolygon/kurtosis-cdk-snapshot- \
#     --tag snapshot-latest-devui \
#     snapshot/snapshots/cdk-<ts>/images/IMAGE_INFO.json
#
# --dry-run: `docker tag` is executed for real (it is local-only, creates no
# network traffic, and is required for the later "does the tag/push command
# actually resolve" rehearsal); `docker push` is only ECHOED, never run, and
# no digest is captured (there is nothing pushed to inspect). This is the
# exact form S11's acceptance criteria calls for: "the exact image tag/push
# commands in --dry-run/echo form".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090,SC1091 # SCRIPT_DIR is resolved at runtime relative to this file (SC1090 on older shellcheck, SC1091 on newer)
source "$SCRIPT_DIR/lib/version-tag.sh"

DRY_RUN=false
REGISTRY_PREFIX=""
TAGS=()
IMAGE_INFO_JSON=""
UNIX_TS=""

usage() {
    cat << 'EOF' >&2
Usage: publish-images.sh [--dry-run] [--unix-ts <epoch-seconds>] --registry-prefix <prefix> --tag <tag> [--tag <extra-tag> ...] <IMAGE_INFO_JSON>
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --registry-prefix)
            REGISTRY_PREFIX="${2:-}"
            shift 2
            ;;
        --tag)
            TAGS+=("${2:-}")
            shift 2
            ;;
        --unix-ts)
            UNIX_TS="${2:-}"
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

# One shared unix-ts for every service in this publish run (not per-service --
# a bundle where different services' immutable tags disagree on when "this
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

log "Registry prefix: $REGISTRY_PREFIX"
log "Tags to publish (uniform, all services): ${TAGS[*]}"
log "Plus one automatic per-service immutable tag: <component-version>-${UNIX_TS}"
log "Dry run: $DRY_RUN"
log ""

SERVICES=$(jq -r '.images | keys[]' "$IMAGE_INFO_JSON")
COUNT=0
FAILED=0

# `.images == {}` (or a malformed IMAGE_INFO.json) would give zero loop
# iterations below and a cheerful exit 0 -- a "successful publish" that pushed
# nothing. Refuse up front.
SERVICE_COUNT=$(jq -r 'if (.images | type) == "object" then (.images | length) else 0 end' "$IMAGE_INFO_JSON")
if [ -z "$SERVICE_COUNT" ] || [ "$SERVICE_COUNT" -lt 1 ]; then
    echo "ERROR: $IMAGE_INFO_JSON lists no images under .images -- nothing to publish" >&2
    exit 1
fi

PUBLISHED_TAGS_JSON="$(dirname "$IMAGE_INFO_JSON")/PUBLISHED_TAGS.json"
echo '{}' > "$PUBLISHED_TAGS_JSON.tmp"

for SVC in $SERVICES; do
    LOCAL_IMAGE=$(jq -r --arg s "$SVC" '.images[$s].name' "$IMAGE_INFO_JSON")
    BASE_IMAGE=$(jq -r --arg s "$SVC" '.images[$s].base_image // ""' "$IMAGE_INFO_JSON")

    # Resolve the immutable per-service tag FIRST and hard-fail the whole
    # script if it cannot be resolved -- never silently skip a service or
    # fall back to a placeholder like "unknown" (see lib/version-tag.sh).
    if ! VERSION_TAG=$(snapshot_versioned_tag "$BASE_IMAGE" "$UNIX_TS"); then
        echo "ERROR: cannot resolve an immutable version tag for service '$SVC' (base_image: '$BASE_IMAGE') -- see above" >&2
        exit 1
    fi
    log "Service $SVC: base_image='$BASE_IMAGE' -> immutable tag '$VERSION_TAG'"

    if ! docker image inspect "$LOCAL_IMAGE" > /dev/null 2>&1; then
        echo "ERROR: local image not found: $LOCAL_IMAGE (service: $SVC)" >&2
        FAILED=1
        continue
    fi

    DIGEST="null"
    for TAG in "${TAGS[@]}" "$VERSION_TAG"; do
        REMOTE_IMAGE="${REGISTRY_PREFIX}${SVC}:${TAG}"

        log "docker tag $LOCAL_IMAGE $REMOTE_IMAGE"
        docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

        if [ "$DRY_RUN" = true ]; then
            log "[DRY-RUN] would run: docker push $REMOTE_IMAGE"
        else
            log "docker push $REMOTE_IMAGE"
            docker push "$REMOTE_IMAGE"

            # Digest is identical across every tag pushed from the same
            # local image, so this only needs to run once per service --
            # tie it to the immutable tag specifically, since that is the
            # one apply-digests.sh will look up afterwards.
            if [ "$TAG" = "$VERSION_TAG" ]; then
                RAW_DIGEST=$(docker buildx imagetools inspect "$REMOTE_IMAGE" --format '{{json .Manifest.Digest}}' 2> /dev/null) || RAW_DIGEST=""
                RESOLVED_DIGEST=""
                if [ -n "$RAW_DIGEST" ]; then
                    RESOLVED_DIGEST=$(jq -r 'if type == "string" and length > 0 then . else "" end' <<< "$RAW_DIGEST" 2> /dev/null || true)
                fi
                if [ -z "$RESOLVED_DIGEST" ]; then
                    echo "ERROR: pushed $REMOTE_IMAGE but could not resolve its manifest digest -- refusing to record a partial/unknown digest" >&2
                    exit 1
                fi
                DIGEST="\"$RESOLVED_DIGEST\""
                log "Digest for $SVC: $RESOLVED_DIGEST"
            fi
        fi
        COUNT=$((COUNT + 1))
    done

    jq --arg svc "$SVC" --arg tag "$VERSION_TAG" --argjson digest "$DIGEST" \
        '. + {($svc): {tag: $tag, digest: $digest}}' \
        "$PUBLISHED_TAGS_JSON.tmp" > "$PUBLISHED_TAGS_JSON.tmp.new"
    mv "$PUBLISHED_TAGS_JSON.tmp.new" "$PUBLISHED_TAGS_JSON.tmp"
done

mv "$PUBLISHED_TAGS_JSON.tmp" "$PUBLISHED_TAGS_JSON"
log ""
log "Wrote per-service published tags/digests: $PUBLISHED_TAGS_JSON"

log ""
log "Processed $COUNT tag(s) across $SERVICE_COUNT service(s)"

if [ "$FAILED" -ne 0 ]; then
    echo "ERROR: one or more local images were missing -- see above" >&2
    exit 1
fi

# +1 for the automatic per-service immutable tag added on top of the uniform
# --tag values.
EXPECTED_COUNT=$((SERVICE_COUNT * (${#TAGS[@]} + 1)))
if [ "$COUNT" -ne "$EXPECTED_COUNT" ]; then
    echo "ERROR: processed $COUNT tag(s), expected $EXPECTED_COUNT ($SERVICE_COUNT services x $((${#TAGS[@]} + 1)) tags)" >&2
    exit 1
fi

exit 0
