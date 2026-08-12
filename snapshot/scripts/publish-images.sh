#!/usr/bin/env bash
#
# Publish the self-contained anvil-aggkit snapshot images built by
# build-images.sh to a remote registry.
#
# Reads <OUTPUT_DIR>/images/IMAGE_INFO.json (written by build-images.sh) and,
# for every service it lists, tags the local image
#   snapshot-<service>:<local-tag>
# as
#   <registry-prefix><service>:<tag>          (for every --tag given)
# then pushes each resulting reference -- or, with --dry-run, prints the
# exact `docker tag` / `docker push` commands without running the push (tag
# is still a purely local, side-effect-free operation, so it always runs; see
# --dry-run below for the precise split).
#
# Usage:
#   publish-images.sh [--dry-run] --registry-prefix <prefix> --tag <tag>
#                      [--tag <extra-tag> ...] <IMAGE_INFO_JSON>
#
# Example (what the snapshot-devui.yml workflow runs):
#   publish-images.sh \
#     --registry-prefix ghcr.io/0xpolygon/kurtosis-cdk-snapshot- \
#     --tag "snapshot-$GIT_SHA_SHORT" --tag snapshot-latest-devui \
#     snapshot/snapshots/cdk-<ts>/images/IMAGE_INFO.json
#
# --dry-run: `docker tag` is executed for real (it is local-only, creates no
# network traffic, and is required for the later "does the tag/push command
# actually resolve" rehearsal); `docker push` is only ECHOED, never run. This
# is the exact form S11's acceptance criteria calls for: "the exact image
# tag/push commands in --dry-run/echo form".

set -euo pipefail

DRY_RUN=false
REGISTRY_PREFIX=""
TAGS=()
IMAGE_INFO_JSON=""

usage() {
    cat << 'EOF' >&2
Usage: publish-images.sh [--dry-run] --registry-prefix <prefix> --tag <tag> [--tag <extra-tag> ...] <IMAGE_INFO_JSON>
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
log "Tags to publish: ${TAGS[*]}"
log "Dry run: $DRY_RUN"
log ""

SERVICES=$(jq -r '.images | keys[]' "$IMAGE_INFO_JSON")
COUNT=0
FAILED=0

for SVC in $SERVICES; do
    LOCAL_IMAGE=$(jq -r --arg s "$SVC" '.images[$s].name' "$IMAGE_INFO_JSON")

    if ! docker image inspect "$LOCAL_IMAGE" > /dev/null 2>&1; then
        echo "ERROR: local image not found: $LOCAL_IMAGE (service: $SVC)" >&2
        FAILED=1
        continue
    fi

    for TAG in "${TAGS[@]}"; do
        REMOTE_IMAGE="${REGISTRY_PREFIX}${SVC}:${TAG}"

        log "docker tag $LOCAL_IMAGE $REMOTE_IMAGE"
        docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

        if [ "$DRY_RUN" = true ]; then
            log "[DRY-RUN] would run: docker push $REMOTE_IMAGE"
        else
            log "docker push $REMOTE_IMAGE"
            docker push "$REMOTE_IMAGE"
        fi
        COUNT=$((COUNT + 1))
    done
done

log ""
log "Processed $COUNT tag(s) across $(echo "$SERVICES" | wc -l) service(s)"

if [ "$FAILED" -ne 0 ]; then
    echo "ERROR: one or more local images were missing -- see above" >&2
    exit 1
fi

exit 0
