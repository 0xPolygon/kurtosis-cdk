#!/usr/bin/env bash
#
# Patch a snapshot bundle's already-written summary.json and
# docker-compose.yml with the real GHCR manifest digests captured by a REAL
# (non-dry-run) publish-images.sh run.
#
# K4 (snapshot-v2-aggkit-e2e plan), group (c) "digest capture": by the time
# publish-images.sh runs, summary.json and docker-compose.yml already exist
# on disk (written earlier in snapshot.sh's pipeline by generate-summary.sh /
# generate-compose.sh, well before any image is pushed). A digest is only
# knowable AFTER a real push, so this script is a deliberately separate,
# later step that mutates those two already-written files -- there are now
# two sequenced writers of docker-compose.yml: generate-compose.sh (which
# writes the tag-based default, pre-publish) and this script (which
# overwrites each service's `image:` line with a digest pin, post-publish).
#
# Reads:
#   <OUTPUT_DIR>/images/PUBLISHED_TAGS.json   (written by publish-images.sh;
#                                              {"<svc>": {"tag", "digest"}})
#   <OUTPUT_DIR>/images/IMAGE_INFO.json       (for the LOCAL image_prefix/tag
#                                              defaults generate-compose.sh
#                                              baked in, so they can be found
#                                              and replaced verbatim)
# Writes (in place, only after every service patches cleanly):
#   <OUTPUT_DIR>/summary.json      -- adds {tag, digest} to
#                                      .images.services.<svc> (alongside the
#                                      existing name/base_image/size)
#   <OUTPUT_DIR>/docker-compose.yml -- rewrites each service's
#                                      `image: ${SNAPSHOT_IMAGE_PREFIX:-...}
#                                      <svc>:${SNAPSHOT_IMAGE_TAG:-...}` line
#                                      to `image: <registry-prefix><svc>@
#                                      <digest>  # <immutable-tag>`
#
# Fails loudly (non-zero, no partial write) if PUBLISHED_TAGS.json is
# missing/empty, any service's digest is null/empty (a dry-run's
# PUBLISHED_TAGS.json has null digests by design -- this script must not be
# run against one), or a service's expected pre-patch image line cannot be
# found verbatim in docker-compose.yml.
#
# Usage:
#   apply-digests.sh --registry-prefix <prefix> <OUTPUT_DIR>

set -euo pipefail

REGISTRY_PREFIX=""
OUTPUT_DIR=""

usage() {
    cat << 'EOF' >&2
Usage: apply-digests.sh --registry-prefix <prefix> <OUTPUT_DIR>
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --registry-prefix)
            REGISTRY_PREFIX="${2:-}"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            if [ -n "$OUTPUT_DIR" ]; then
                echo "Unexpected extra argument: $1" >&2
                usage
            fi
            OUTPUT_DIR="$1"
            shift
            ;;
    esac
done

if [ -z "$REGISTRY_PREFIX" ] || [ -z "$OUTPUT_DIR" ]; then
    usage
fi

for cmd in jq docker; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: required command '$cmd' not found" >&2
        exit 1
    fi
done

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

PUBLISHED_TAGS_JSON="$OUTPUT_DIR/images/PUBLISHED_TAGS.json"
IMAGE_INFO_JSON="$OUTPUT_DIR/images/IMAGE_INFO.json"
SUMMARY_JSON="$OUTPUT_DIR/summary.json"
COMPOSE_FILE="$OUTPUT_DIR/docker-compose.yml"

for f in "$PUBLISHED_TAGS_JSON" "$IMAGE_INFO_JSON" "$SUMMARY_JSON" "$COMPOSE_FILE"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: required input not found: $f" >&2
        exit 1
    fi
done

SERVICE_COUNT=$(jq -r 'if type == "object" then length else 0 end' "$PUBLISHED_TAGS_JSON")
if [ -z "$SERVICE_COUNT" ] || [ "$SERVICE_COUNT" -lt 1 ]; then
    echo "ERROR: $PUBLISHED_TAGS_JSON lists no services -- nothing to patch" >&2
    exit 1
fi

# Every digest must be present (real push) -- refuse a dry-run's
# PUBLISHED_TAGS.json (all digests null) outright, rather than silently
# writing an unpinned or half-pinned bundle.
MISSING_DIGESTS=$(jq -r '[to_entries[] | select(.value.digest == null or .value.digest == "") | .key] | join(", ")' "$PUBLISHED_TAGS_JSON")
if [ -n "$MISSING_DIGESTS" ]; then
    echo "ERROR: $PUBLISHED_TAGS_JSON has no digest for: $MISSING_DIGESTS" >&2
    echo "       (digests only exist after a REAL push -- this script must not run against a --dry-run publish)" >&2
    exit 1
fi

LOCAL_IMAGE_PREFIX=$(jq -r '.image_prefix' "$IMAGE_INFO_JSON")
LOCAL_IMAGE_TAG=$(jq -r '.tag' "$IMAGE_INFO_JSON")

WORK_SUMMARY=$(mktemp)
WORK_COMPOSE=$(mktemp)
cp "$SUMMARY_JSON" "$WORK_SUMMARY"
cp "$COMPOSE_FILE" "$WORK_COMPOSE"
cleanup() { rm -f "$WORK_SUMMARY" "$WORK_COMPOSE"; }
trap cleanup EXIT

# bash pattern-substitution (${var//pattern/replacement}) uses glob
# matching, not regex, and none of the characters in these patterns
# ($, {, }, :, -) are glob-special -- so a plain literal substring match is
# exact and safe here, with none of the escaping headaches a sed/regex
# approach would need.
COMPOSE_CONTENT=$(cat "$WORK_COMPOSE")

PATCHED=0
for SVC in $(jq -r 'keys[]' "$PUBLISHED_TAGS_JSON"); do
    TAG=$(jq -r --arg s "$SVC" '.[$s].tag' "$PUBLISHED_TAGS_JSON")
    DIGEST=$(jq -r --arg s "$SVC" '.[$s].digest' "$PUBLISHED_TAGS_JSON")

    log "Patching $SVC: tag=$TAG digest=$DIGEST"

    jq --arg svc "$SVC" --arg tag "$TAG" --arg digest "$DIGEST" \
        '.images.services[$svc] as $existing
         | if $existing == null then
             error("summary.json has no images.services entry for '\''" + $svc + "'\''")
           else
             .images.services[$svc] = ($existing + {tag: $tag, digest: $digest})
           end' \
        "$WORK_SUMMARY" > "$WORK_SUMMARY.new"
    mv "$WORK_SUMMARY.new" "$WORK_SUMMARY"

    OLD_REF="\${SNAPSHOT_IMAGE_PREFIX:-${LOCAL_IMAGE_PREFIX}}${SVC}:\${SNAPSHOT_IMAGE_TAG:-${LOCAL_IMAGE_TAG}}"
    NEW_REF="${REGISTRY_PREFIX}${SVC}@${DIGEST}  # ${TAG}"

    if [[ "$COMPOSE_CONTENT" != *"$OLD_REF"* ]]; then
        echo "ERROR: expected pre-patch image reference not found in $COMPOSE_FILE for service '$SVC':" >&2
        echo "       $OLD_REF" >&2
        exit 1
    fi
    COMPOSE_CONTENT="${COMPOSE_CONTENT//$OLD_REF/$NEW_REF}"
    PATCHED=$((PATCHED + 1))
done

if [ "$PATCHED" -ne "$SERVICE_COUNT" ]; then
    echo "ERROR: patched $PATCHED service(s), expected $SERVICE_COUNT" >&2
    exit 1
fi

printf '%s' "$COMPOSE_CONTENT" > "$WORK_COMPOSE"

# Validate the patched compose file resolves before touching the real files
# -- never leave a broken docker-compose.yml behind.
if ! docker compose -f "$WORK_COMPOSE" config > /dev/null; then
    echo "ERROR: patched $COMPOSE_FILE fails 'docker compose config' -- not writing it" >&2
    exit 1
fi
if ! jq empty "$WORK_SUMMARY" > /dev/null 2>&1; then
    echo "ERROR: patched $SUMMARY_JSON is not valid JSON -- not writing it" >&2
    exit 1
fi

cp "$WORK_SUMMARY" "$SUMMARY_JSON"
cp "$WORK_COMPOSE" "$COMPOSE_FILE"

log ""
log "Patched digest + immutable tag into $SERVICE_COUNT service(s) in:"
log "  $SUMMARY_JSON"
log "  $COMPOSE_FILE"

exit 0
