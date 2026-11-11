#!/usr/bin/env bash
#
# Verify healthchecks in generated docker-compose.yml
# This script validates that all healthchecks use available tools (curl, not wget)
# and that critical services have proper healthcheck configurations
#
# Usage: verify-healthchecks.sh [--flavor default|anvil-aggkit] <SNAPSHOT_DIR>
#
# Flavor "default" (the pre-existing behaviour, unchanged): despite the
# ERRORS bookkeeping below, no code path in this flavor ever increments
# ERRORS, so it always exits 0. That is a known, long-standing limitation of
# the default flavor, which this script does not change.
#
# Flavor "anvil-aggkit": real checks that DO set ERRORS and can fail --
# the compose file defines the expected set of components, every service has
# a healthcheck, only the dev-ui is profile-gated, `depends_on` gates on
# service_healthy, and the bundle stays bind-mount/volume free (the
# "self-contained" contract). verify-healthchecks_test.sh covers each check
# with a failing fixture.
#
set -euo pipefail

FLAVOR="default"
while [ $# -gt 0 ]; do
    case "$1" in
        --flavor)
            if [ $# -lt 2 ]; then
                echo "ERROR: --flavor requires a value" >&2
                exit 1
            fi
            FLAVOR="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--flavor default|anvil-aggkit] <SNAPSHOT_DIR>" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 [--flavor default|anvil-aggkit] <SNAPSHOT_DIR>" >&2
    exit 1
fi

# An unrecognised flavor must fail rather than silently select the default
# path, whose checks are a strict subset of the anvil-aggkit ones.
case "$FLAVOR" in
    default | anvil-aggkit) ;;
    *)
        echo "ERROR: unknown flavor: '$FLAVOR' (expected 'default' or 'anvil-aggkit')" >&2
        exit 1
        ;;
esac

SNAPSHOT_DIR="$1"
COMPOSE_FILE="$SNAPSHOT_DIR/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[VERIFY]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check if docker-compose.yml exists
if [ ! -f "$COMPOSE_FILE" ]; then
    error "docker-compose.yml not found at: $COMPOSE_FILE"
    exit 1
fi

log "Verifying healthchecks in: $COMPOSE_FILE"

ERRORS=0
WARNINGS=0

# ============================================================================
# Flavor: anvil-aggkit
#
# Real checks, unlike the default flavor below. Everything is read from the
# resolved compose model (`docker compose config --format json`) rather than
# from the YAML text, so comments cannot satisfy a check and a profile-gated
# service cannot hide from one. `--profile '*'` only affects what `config`
# prints; it starts nothing.
#
# The default flavor continues, byte-for-byte unchanged, below this block.
# ============================================================================
if [ "$FLAVOR" = "anvil-aggkit" ]; then
    if ! command -v jq &> /dev/null; then
        error "jq is required for --flavor anvil-aggkit"
        exit 1
    fi

    COMPOSE_JSON=$(docker compose -f "$COMPOSE_FILE" --profile '*' config --format json 2>/dev/null || true)
    if [ -z "$COMPOSE_JSON" ] || ! echo "$COMPOSE_JSON" | jq -e '.services | type == "object" and length > 0' > /dev/null 2>&1; then
        error "docker compose config --format json failed or lists no services for $COMPOSE_FILE"
        ERRORS=$((ERRORS + 1))
        COMPOSE_JSON='{"services":{}}'
    fi
    SERVICE_NAMES=$(echo "$COMPOSE_JSON" | jq -r '.services | keys[]')

    log ""
    log "=== [anvil-aggkit] The compose file defines the expected components ==="
    # Fixed expectation, deliberately not derived from discovery.json: a
    # component that discovery missed must not silently drop out of the
    # check. One L1 anvil, one or more L2 anvils with one aggkit each, one
    # agglayer, one aggkit-proxy, one bridge-ui haproxy and one dev-ui.
    count_services() {
        local n
        n=$(echo "$SERVICE_NAMES" | grep -cE "$1" || true)
        echo "${n:-0}"
    }
    expect_exactly_one() {
        local role="$1" pattern="$2" n
        n=$(count_services "$pattern")
        if [ "$n" -eq 1 ]; then
            log "✓ exactly one $role service"
        else
            error "✗ expected exactly one $role service (/$pattern/), found $n"
            ERRORS=$((ERRORS + 1))
        fi
    }
    expect_exactly_one "L1 anvil" '^anvil-[0-9]{3}$'
    expect_exactly_one "agglayer" '^agglayer$'
    expect_exactly_one "aggkit-proxy" '^aggkit-proxy-[0-9]{3}$'
    expect_exactly_one "bridge-ui haproxy" '^agglayer-dev-ui-proxy-[0-9]{3}$'
    expect_exactly_one "dev-ui" '^agglayer-dev-ui-[0-9]{3}$'
    L2_ANVIL_COUNT=$(count_services '^l2-anvil-[0-9]{3}$')
    AGGKIT_COUNT=$(count_services '^aggkit-[0-9]{3}$')
    if [ "$L2_ANVIL_COUNT" -ge 1 ] && [ "$L2_ANVIL_COUNT" -eq "$AGGKIT_COUNT" ]; then
        log "✓ $L2_ANVIL_COUNT L2 anvil(s) with $AGGKIT_COUNT aggkit service(s)"
    else
        error "✗ expected at least one L2 anvil and one aggkit per L2 anvil, found $L2_ANVIL_COUNT l2-anvil and $AGGKIT_COUNT aggkit service(s)"
        ERRORS=$((ERRORS + 1))
    fi
    for prefix in $(echo "$SERVICE_NAMES" | grep -E '^l2-anvil-[0-9]{3}$' | sed 's/^l2-anvil-//'); do
        if ! echo "$SERVICE_NAMES" | grep -qx "aggkit-$prefix"; then
            error "✗ l2-anvil-$prefix has no aggkit-$prefix service"
            ERRORS=$((ERRORS + 1))
        fi
    done

    log ""
    log "=== [anvil-aggkit] Every service has a healthcheck ==="
    # A healthcheck is a non-empty test that is not disabled (`disable: true`
    # or `test: ["NONE"]`).
    NO_HEALTHCHECK=$(echo "$COMPOSE_JSON" | jq -r '
        .services | to_entries[]
        | select(
            (.value.healthcheck | type) != "object"
            or .value.healthcheck.disable == true
            or ((.value.healthcheck.test // []) | length) == 0
            or .value.healthcheck.test == ["NONE"])
        | .key')
    for service in $SERVICE_NAMES; do
        if echo "$NO_HEALTHCHECK" | grep -qx "$service"; then
            error "✗ $service: NO healthcheck defined -- required for every anvil-aggkit service"
            ERRORS=$((ERRORS + 1))
        else
            log "✓ $service: has a healthcheck"
        fi
    done

    log ""
    log "=== [anvil-aggkit] Only the dev-ui is profile-gated ==="
    # The dev-ui is the one service behind `profiles: ["devui"]`, so
    # `docker compose up` does not start it; every other service must be in
    # the default set. Two regressions are caught: the dev-ui losing its
    # profile (it would start by default) and another service gaining one
    # (it would silently drop out of the default stack).
    PROFILED=$(echo "$COMPOSE_JSON" | jq -r '.services | to_entries[] | select((.value.profiles // []) | length > 0) | .key')
    for service in $SERVICE_NAMES; do
        if echo "$service" | grep -qE '^agglayer-dev-ui-[0-9]{3}$'; then
            if echo "$COMPOSE_JSON" | jq -e --arg s "$service" '.services[$s].profiles // [] | index("devui") != null' > /dev/null; then
                log "✓ $service: behind --profile devui, as intended"
            else
                error "✗ $service must stay behind --profile devui"
                ERRORS=$((ERRORS + 1))
            fi
        elif echo "$PROFILED" | grep -qx "$service"; then
            error "✗ $service is profile-gated; only the dev-ui may be"
            ERRORS=$((ERRORS + 1))
        fi
    done

    log ""
    log "=== [anvil-aggkit] depends_on gates on service_healthy, not just service_started ==="
    # A `depends_on` list entry (or a map entry without condition:
    # service_healthy) starts a service as soon as its dependency's
    # CONTAINER starts, not once it is healthy -- exactly the ordering bug
    # this flavor's compose is supposed to avoid (anvil/agglayer/aggkit all
    # need their upstream truly ready first). `docker compose config
    # --format json` normalizes depends_on to the long map form regardless
    # of how it was written, so this is robust to either compose syntax.
    UNGATED=$(echo "$COMPOSE_JSON" | jq -r '
        .services | to_entries[] as $s
        | ($s.value.depends_on // {}) | to_entries[] as $d
        | select($d.value.condition != "service_healthy")
        | "\($s.key) -> \($d.key) (condition=\($d.value.condition // "none"))"
    ')
    if [ -n "$UNGATED" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            error "✗ depends_on not gated on service_healthy: $line"
            ERRORS=$((ERRORS + 1))
        done <<< "$UNGATED"
    else
        log "✓ every depends_on entry is gated on condition: service_healthy"
    fi

    log ""
    log "=== [anvil-aggkit] Self-contained: no bind mounts, no named volumes ==="
    BAD_VOLUMES=$(echo "$COMPOSE_JSON" | jq -r '
        .services | to_entries[] as $s
        | ($s.value.volumes // [])[] as $v
        | "\($s.key): \($v.source // $v)"
    ')
    if [ -n "$BAD_VOLUMES" ]; then
        error "✗ found bind mount(s)/volume(s) -- the bundle must be self-contained:"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            error "    $line"
            ERRORS=$((ERRORS + 1))
        done <<< "$BAD_VOLUMES"
    else
        log "✓ no bind mounts or volumes"
    fi

    log ""
    log "=== [anvil-aggkit] Healthcheck Verification Summary ==="
    if [ "$ERRORS" -eq 0 ]; then
        log "✓ All anvil-aggkit healthcheck/compose checks passed"
    else
        error "✗ Found $ERRORS error(s)"
    fi
    if [ "$WARNINGS" -gt 0 ]; then
        warn "! Found $WARNINGS warning(s)"
    fi
    log ""
    if [ "$ERRORS" -eq 0 ]; then
        log "Healthcheck verification PASSED"
        exit 0
    else
        error "Healthcheck verification FAILED"
        exit 1
    fi
fi

# Function to check a service's healthcheck
check_service_healthcheck() {
    local service_name="$1"
    local required="${2:-false}"  # Is healthcheck required for this service?

    log "Checking $service_name healthcheck..."

    # Check if service exists
    if ! grep -q "^  $service_name:" "$COMPOSE_FILE"; then
        if [ "$required" = "true" ]; then
            warn "Service $service_name not found (may not be configured in this snapshot)"
        fi
        return 0
    fi

    # Extract service section
    SERVICE_SECTION=$(sed -n "/^  $service_name:/,/^  [a-z]/p" "$COMPOSE_FILE")

    # Check if healthcheck exists
    if ! echo "$SERVICE_SECTION" | grep -q "healthcheck:"; then
        if [ "$required" = "true" ]; then
            warn "✗ $service_name: No healthcheck defined (acceptable for minimal images)"
            WARNINGS=$((WARNINGS + 1))
        else
            log "○ $service_name: No healthcheck (optional)"
        fi
        return 0
    fi

    # Extract healthcheck test command
    HEALTHCHECK_TEST=$(echo "$SERVICE_SECTION" | grep -A 1 "test:" | tail -1 | sed 's/^[[:space:]]*//')

    # Check if using wget (acceptable for containers without curl)
    if echo "$HEALTHCHECK_TEST" | grep -q "wget"; then
        log "✓ $service_name: Healthcheck uses 'wget'"
    # Check if using curl (preferred)
    elif echo "$HEALTHCHECK_TEST" | grep -q "curl"; then
        log "✓ $service_name: Healthcheck uses 'curl'"
    else
        warn "✓ $service_name: Healthcheck uses custom command"
        WARNINGS=$((WARNINGS + 1))
    fi

    # For op-node services, verify it uses a proper RPC check
    if [[ "$service_name" == op-node-* ]]; then
        if echo "$HEALTHCHECK_TEST" | grep -q "optimism_syncStatus\|metrics"; then
            log "✓ $service_name: Uses proper health endpoint (optimism_syncStatus or metrics)"
        else
            warn "✗ $service_name: May not be using optimal health endpoint"
            warn "  Command: $HEALTHCHECK_TEST"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi

    return 0
}

# Check critical services
log ""
log "=== Checking Critical Services ==="

check_service_healthcheck "geth" false
check_service_healthcheck "beacon" false
check_service_healthcheck "validator" false

# Check for L2 services (op-node is critical for aggkit)
log ""
log "=== Checking L2 Services ==="

# Find all op-node services
OP_NODE_SERVICES=$(grep -E "^  op-node-[0-9]+:" "$COMPOSE_FILE" | sed 's/://g' | awk '{print $1}' || true)

if [ -z "$OP_NODE_SERVICES" ]; then
    log "No op-node services found (L2 not configured)"
else
    for service in $OP_NODE_SERVICES; do
        check_service_healthcheck "$service" false
    done
fi

# Find all op-reth services
OP_RETH_SERVICES=$(grep -E "^  op-reth-[0-9]+:" "$COMPOSE_FILE" | sed 's/://g' | awk '{print $1}' || true)

if [ -n "$OP_RETH_SERVICES" ]; then
    for service in $OP_RETH_SERVICES; do
        check_service_healthcheck "$service" false
    done
fi

# Check aggkit services (depends on op-node being healthy)
AGGKIT_SERVICES=$(grep -E "^  aggkit-[0-9]+:" "$COMPOSE_FILE" | sed 's/://g' | awk '{print $1}' || true)

if [ -n "$AGGKIT_SERVICES" ]; then
    for service in $AGGKIT_SERVICES; do
        check_service_healthcheck "$service" false
    done
fi

# Check agglayer
log ""
log "=== Checking Agglayer Service ==="
check_service_healthcheck "agglayer" false

# Summary
log ""
log "=== Healthcheck Verification Summary ==="
if [ $ERRORS -eq 0 ]; then
    log "✓ All critical healthchecks are properly configured"
else
    error "✗ Found $ERRORS error(s) in healthcheck configuration"
fi

if [ $WARNINGS -gt 0 ]; then
    warn "! Found $WARNINGS warning(s)"
fi

log ""
if [ $ERRORS -eq 0 ]; then
    log "Healthcheck verification PASSED"
    exit 0
else
    error "Healthcheck verification FAILED"
    exit 1
fi
