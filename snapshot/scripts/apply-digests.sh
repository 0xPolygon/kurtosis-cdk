#!/usr/bin/env bash
#
# Patch a snapshot bundle's already-written summary.json and
# docker-compose.yml with the real GHCR manifest digests captured by a REAL
# (non-dry-run) publish-images.sh run.
#
# By the time publish-images.sh runs, summary.json and docker-compose.yml
# already exist on disk (written earlier in snapshot.sh's pipeline by
# generate-summary.sh / generate-compose.sh, well before any image is
# pushed). A digest is only knowable AFTER a real push, so this script is a
# deliberately separate, later step that mutates those two already-written
# files -- there are two sequenced writers of docker-compose.yml:
# generate-compose.sh (which writes the tag-based default, pre-publish) and
# this script (which overwrites each service's `image:` line with a digest
# pin, post-publish).
#
# Reads:
#   <OUTPUT_DIR>/images/PUBLISHED_TAGS.json   (written by publish-images.sh;
#                                              {"<svc>": {"repo", "tag",
#                                              "digest", "aliases"}})
#   <OUTPUT_DIR>/images/IMAGE_INFO.json       (for the LOCAL image_prefix/tag
#                                              defaults generate-compose.sh
#                                              baked in, so they can be found
#                                              and replaced verbatim, and for
#                                              the expected set of services)
# Writes (in place, only after every check below passed):
#   <OUTPUT_DIR>/summary.json      -- adds {tag, digest} to
#                                      .images.services.<svc> (alongside the
#                                      existing name/base_image/size)
#   <OUTPUT_DIR>/docker-compose.yml -- rewrites each service's
#                                      `image: ${SNAPSHOT_IMAGE_PREFIX:-...}
#                                      <svc>:${SNAPSHOT_IMAGE_TAG:-...}` line
#                                      to `image: <repo>@<digest>  # <tag>`
#                                      with the repo recorded at publish time
#   <OUTPUT_DIR>/docker-compose.mounts.yml (OPTIONAL -- only present for
#                                      the anvil-aggkit flavor) -- same
#                                      rewrite, applied ONLY to the services
#                                      that still use that ref pattern there
#                                      (anvil family, haproxy, dev-ui). The
#                                      override-able services in that file
#                                      (agglayer, aggkit-00X,
#                                      aggkit-proxy-001) intentionally use a
#                                      bare upstream image ref
#                                      (${AGGLAYER_IMAGE:-...} /
#                                      ${AGGKIT_IMAGE:-...}), never
#                                      republished under this repo's own
#                                      digest, so a miss for those services
#                                      in that file is expected, not an
#                                      error.
#
# Fails loudly (non-zero, no partial write) if
#   - PUBLISHED_TAGS.json is missing/empty, its services differ from the ones
#     in IMAGE_INFO.json, or an entry has no repo, tag or a digest that is
#     not `sha256:<64 hex>` (a dry-run's PUBLISHED_TAGS.json has null digests
#     by design -- this script must not be run against one);
#   - --registry-prefix is given and a recorded repo is not
#     <prefix><service>;
#   - a service's expected pre-patch image line cannot be found verbatim in
#     docker-compose.yml, or any ${SNAPSHOT_IMAGE_PREFIX...} reference is
#     left in either compose file afterwards;
#   - the resolved compose files do not reference exactly <repo>@<digest>
#     for every republished service;
#   - a pinned <repo>@<digest> cannot be found in the registry (skip with
#     --skip-registry-check, for hosts without registry access).
# --smoke-test additionally pulls the digest-pinned images, brings the
# patched docker-compose.yml up with `--wait` and tears it down again; run it
# on a host whose ports are free.
#
# Usage:
#   apply-digests.sh [--registry-prefix <prefix>] [--skip-registry-check]
#                    [--smoke-test] <OUTPUT_DIR>

set -euo pipefail

REGISTRY_PREFIX=""
OUTPUT_DIR=""
REGISTRY_CHECK=true
SMOKE_TEST=false

usage() {
    cat << 'EOF' >&2
Usage: apply-digests.sh [--registry-prefix <prefix>] [--skip-registry-check] [--smoke-test] <OUTPUT_DIR>
EOF
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --registry-prefix)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                echo "ERROR: --registry-prefix requires a value" >&2
                usage
            fi
            REGISTRY_PREFIX="$2"
            shift 2
            ;;
        --skip-registry-check)
            REGISTRY_CHECK=false
            shift
            ;;
        --smoke-test)
            SMOKE_TEST=true
            shift
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

if [ -z "$OUTPUT_DIR" ]; then
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
# The mounts-variant compose file (generate-compose.sh's
# generate_mounts_compose) uses the SAME ${SNAPSHOT_IMAGE_PREFIX:-...}<svc>:
# ${SNAPSHOT_IMAGE_TAG:-...} ref pattern as docker-compose.yml for the
# anvil family, haproxy and dev-ui, so it gets the SAME digest patch applied
# below. It is OPTIONAL (only the anvil-aggkit flavor emits it) and
# deliberately NOT required to exist -- other flavors/older bundles have no
# such file.
MOUNTS_COMPOSE_FILE="$OUTPUT_DIR/docker-compose.mounts.yml"

for f in "$PUBLISHED_TAGS_JSON" "$IMAGE_INFO_JSON" "$SUMMARY_JSON" "$COMPOSE_FILE"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: required input not found: $f" >&2
        exit 1
    fi
done

HAS_MOUNTS_FILE=false
if [ -f "$MOUNTS_COMPOSE_FILE" ]; then
    HAS_MOUNTS_FILE=true
fi

SERVICE_COUNT=$(jq -r 'if type == "object" then length else 0 end' "$PUBLISHED_TAGS_JSON")
if [ -z "$SERVICE_COUNT" ] || [ "$SERVICE_COUNT" -lt 1 ]; then
    echo "ERROR: $PUBLISHED_TAGS_JSON lists no services -- nothing to patch" >&2
    exit 1
fi

# The services that were published must be exactly the services that were
# built; a service missing here would silently stay on a local tag.
PUBLISHED_KEYS=$(jq -c 'keys' "$PUBLISHED_TAGS_JSON")
BUILT_KEYS=$(jq -c '.images | keys' "$IMAGE_INFO_JSON")
if [ "$PUBLISHED_KEYS" != "$BUILT_KEYS" ]; then
    echo "ERROR: $PUBLISHED_TAGS_JSON and $IMAGE_INFO_JSON list different services:" >&2
    echo "       published: $PUBLISHED_KEYS" >&2
    echo "       built:     $BUILT_KEYS" >&2
    exit 1
fi

# Every digest must be present (real push) -- refuse a dry-run's
# PUBLISHED_TAGS.json (all digests null) outright, rather than silently
# writing an unpinned or half-pinned bundle. Each entry must also carry the
# repository it was pushed to and a well-formed digest and tag.
BAD_ENTRIES=$(jq -r '
    [to_entries[]
     | select(
         (.value | type) != "object"
         or ((.value.digest // "") | test("^sha256:[0-9a-f]{64}$") | not)
         or ((.value.tag // "") | test("^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$") | not)
         or ((.value.repo // "") | test("^[a-z0-9]+([._-][a-z0-9]+)*(:[0-9]+)?(/[a-z0-9]+([._-][a-z0-9]+)*)+$") | not))
     | .key] | join(", ")' "$PUBLISHED_TAGS_JSON")
if [ -n "$BAD_ENTRIES" ]; then
    echo "ERROR: $PUBLISHED_TAGS_JSON has a missing or malformed repo/tag/digest for: $BAD_ENTRIES" >&2
    echo "       (digests only exist after a REAL push -- this script must not run against a --dry-run publish)" >&2
    exit 1
fi

if [ -n "$REGISTRY_PREFIX" ]; then
    WRONG_REPOS=$(jq -r --arg p "$REGISTRY_PREFIX" '[to_entries[] | select(.value.repo != ($p + .key)) | .key] | join(", ")' "$PUBLISHED_TAGS_JSON")
    if [ -n "$WRONG_REPOS" ]; then
        echo "ERROR: --registry-prefix '$REGISTRY_PREFIX' does not match the repositories recorded at publish time for: $WRONG_REPOS" >&2
        exit 1
    fi
fi

if [ "$REGISTRY_CHECK" = true ]; then
    log "Checking that every pinned digest exists in the registry..."
    while IFS=$'\t' read -r SVC REPO DIGEST; do
        if ! docker buildx imagetools inspect "${REPO}@${DIGEST}" > /dev/null 2>&1; then
            echo "ERROR: ${REPO}@${DIGEST} (service $SVC) cannot be found in the registry" >&2
            exit 1
        fi
    done < <(jq -r 'to_entries[] | [.key, .value.repo, .value.digest] | @tsv' "$PUBLISHED_TAGS_JSON")
fi

LOCAL_IMAGE_PREFIX=$(jq -r '.image_prefix' "$IMAGE_INFO_JSON")
LOCAL_IMAGE_TAG=$(jq -r '.tag' "$IMAGE_INFO_JSON")

WORK_SUMMARY=$(mktemp)
WORK_COMPOSE=$(mktemp)
cp "$SUMMARY_JSON" "$WORK_SUMMARY"
cp "$COMPOSE_FILE" "$WORK_COMPOSE"
CLEANUP_FILES=("$WORK_SUMMARY" "$WORK_SUMMARY.new" "$WORK_COMPOSE")
WORK_MOUNTS_COMPOSE=""
if [ "$HAS_MOUNTS_FILE" = true ]; then
    WORK_MOUNTS_COMPOSE=$(mktemp)
    cp "$MOUNTS_COMPOSE_FILE" "$WORK_MOUNTS_COMPOSE"
    CLEANUP_FILES+=("$WORK_MOUNTS_COMPOSE")
fi
trap 'rm -f "${CLEANUP_FILES[@]}"' EXIT

# The reference to find is quoted, so glob characters in it (a --tag or an
# enclave name with `*`, `?` or `[`) match literally; the replacement is
# quoted so that a `&` in it is not expanded to the matched text.
COMPOSE_CONTENT=$(cat "$WORK_COMPOSE")
MOUNTS_CONTENT=""
if [ "$HAS_MOUNTS_FILE" = true ]; then
    MOUNTS_CONTENT=$(cat "$WORK_MOUNTS_COMPOSE")
fi

PATCHED=0
MOUNTS_PATCHED=0
EXPECTED_IMAGES=()
while IFS=$'\t' read -r SVC REPO TAG DIGEST; do
    log "Patching $SVC: repo=$REPO tag=$TAG digest=$DIGEST"

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
    NEW_REF="${REPO}@${DIGEST}  # ${TAG}"

    if [[ "$COMPOSE_CONTENT" != *"$OLD_REF"* ]]; then
        echo "ERROR: expected pre-patch image reference not found in $COMPOSE_FILE for service '$SVC':" >&2
        echo "       $OLD_REF" >&2
        exit 1
    fi
    COMPOSE_CONTENT="${COMPOSE_CONTENT//"$OLD_REF"/"$NEW_REF"}"
    PATCHED=$((PATCHED + 1))
    EXPECTED_IMAGES+=("${REPO}@${DIGEST}")

    # docker-compose.mounts.yml: patch IF this service still uses the same
    # derived-image ref pattern there (the anvil family, haproxy, dev-ui).
    # agglayer/aggkit-00X/aggkit-proxy-001 do NOT -- their refs in that file
    # are bare upstream image strings (${AGGLAYER_IMAGE:-...} /
    # ${AGGKIT_IMAGE:-...}), never republished under this repo's own digest,
    # so a miss there is expected and not an error.
    if [ "$HAS_MOUNTS_FILE" = true ] && [[ "$MOUNTS_CONTENT" == *"$OLD_REF"* ]]; then
        MOUNTS_CONTENT="${MOUNTS_CONTENT//"$OLD_REF"/"$NEW_REF"}"
        MOUNTS_PATCHED=$((MOUNTS_PATCHED + 1))
    fi
done < <(jq -r 'to_entries[] | [.key, .value.repo, .value.tag, .value.digest] | @tsv' "$PUBLISHED_TAGS_JSON")

if [ "$PATCHED" -ne "$SERVICE_COUNT" ]; then
    echo "ERROR: patched $PATCHED service(s), expected $SERVICE_COUNT" >&2
    exit 1
fi
if [ "$HAS_MOUNTS_FILE" = true ] && [ "$MOUNTS_PATCHED" -lt 1 ]; then
    echo "ERROR: $MOUNTS_COMPOSE_FILE exists but no service reference in it could be patched" >&2
    exit 1
fi

# No reference to a locally built image may survive in a patched file: a
# service that stayed on a tag would give a bundle that is only partly pinned.
check_no_residual_refs() {
    local content="$1" file="$2" residual
    residual=$(grep -nE '^[[:space:]]*image:.*SNAPSHOT_IMAGE_PREFIX' <<< "$content" || true)
    if [ -n "$residual" ]; then
        echo "ERROR: $file still references a locally built image after patching:" >&2
        echo "$residual" >&2
        exit 1
    fi
}
check_no_residual_refs "$COMPOSE_CONTENT" "$COMPOSE_FILE"
if [ "$HAS_MOUNTS_FILE" = true ]; then
    check_no_residual_refs "$MOUNTS_CONTENT" "$MOUNTS_COMPOSE_FILE"
fi

printf '%s\n' "$COMPOSE_CONTENT" > "$WORK_COMPOSE"

# The patched compose file must resolve, and every republished image must
# appear in it exactly as <repo>@<digest>. Validated before touching the real
# files -- never leave a broken docker-compose.yml behind. --profile devui
# includes the profile-gated dev-ui service.
check_resolved_images() {
    local compose="$1" file="$2" mode="$3" resolved expected missing
    if ! resolved=$(docker compose --profile devui -f "$compose" config --format json); then
        echo "ERROR: patched $file fails 'docker compose config' -- not writing it" >&2
        exit 1
    fi
    expected=$(printf '%s\n' "${EXPECTED_IMAGES[@]}" | jq -R . | jq -s .)
    if [ "$mode" = "all" ]; then
        missing=$(jq -r --argjson exp "$expected" '[.services[].image] as $got | $exp - $got | join(", ")' <<< "$resolved")
        if [ -n "$missing" ]; then
            echo "ERROR: $file does not reference the published image(s): $missing" >&2
            exit 1
        fi
    fi
    # Pinned images in the file must all be ones that were published.
    missing=$(jq -r --argjson exp "$expected" '[.services[].image | select(contains("@sha256:"))] - $exp | join(", ")' <<< "$resolved")
    if [ -n "$missing" ]; then
        echo "ERROR: $file pins image(s) that were not part of this publish: $missing" >&2
        exit 1
    fi
}
check_resolved_images "$WORK_COMPOSE" "$COMPOSE_FILE" all

if ! jq empty "$WORK_SUMMARY" > /dev/null 2>&1; then
    echo "ERROR: patched $SUMMARY_JSON is not valid JSON -- not writing it" >&2
    exit 1
fi

if [ "$HAS_MOUNTS_FILE" = true ]; then
    printf '%s\n' "$MOUNTS_CONTENT" > "$WORK_MOUNTS_COMPOSE"
    check_resolved_images "$WORK_MOUNTS_COMPOSE" "$MOUNTS_COMPOSE_FILE" subset
fi

cp "$WORK_SUMMARY" "$SUMMARY_JSON"
cp "$WORK_COMPOSE" "$COMPOSE_FILE"
if [ "$HAS_MOUNTS_FILE" = true ]; then
    cp "$WORK_MOUNTS_COMPOSE" "$MOUNTS_COMPOSE_FILE"
fi

log ""
log "Patched digest + immutable tag into $SERVICE_COUNT service(s) in:"
log "  $SUMMARY_JSON"
log "  $COMPOSE_FILE"
if [ "$HAS_MOUNTS_FILE" = true ]; then
    log "  $MOUNTS_COMPOSE_FILE ($MOUNTS_PATCHED of $SERVICE_COUNT service(s) -- the rest are bare upstream refs by design, see this file's header comment)"
fi

if [ "$SMOKE_TEST" = true ]; then
    log "Smoke test: pulling the digest-pinned images and bringing the bundle up..."
    trap 'docker compose -f "$COMPOSE_FILE" down -v > /dev/null 2>&1 || true; rm -f "${CLEANUP_FILES[@]}"' EXIT
    docker compose -f "$COMPOSE_FILE" pull
    docker compose -f "$COMPOSE_FILE" up -d --wait
    docker compose -f "$COMPOSE_FILE" down -v
    log "Smoke test passed: the published bundle starts and every service is healthy"
fi

exit 0
