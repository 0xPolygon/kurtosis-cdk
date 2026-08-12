#!/usr/bin/env bash
#
# Verify healthchecks in generated docker-compose.yml
# This script validates that all healthchecks use available tools (curl, not wget)
# and that critical services have proper healthcheck configurations
#
# Usage: verify-healthchecks.sh [--flavor default|anvil-aggkit] <SNAPSHOT_DIR>
#
# Flavor "default" (the pre-existing behaviour, unchanged -- see S9's outcome
# notes): despite the ERRORS bookkeeping below, no code path in this flavor
# ever increments ERRORS, so it always exits 0. That is a known, long-
# standing bug, but fixing it is explicitly out of scope for the default
# flavor (S9 fixes it for anvil-aggkit only; see the plan).
#
# Flavor "anvil-aggkit" (S9): real checks that DO set ERRORS and can fail --
# every expected service has a healthcheck, `depends_on` gates on
# service_healthy where S8 wires it, and the bundle stays bind-mount/volume
# free (the "self-contained" contract).
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
# Flavor: anvil-aggkit (S9)
#
# Real checks, unlike the default flavor below: this block is the actual fix
# for "verify-healthchecks.sh always exits 0". It cross-checks the compose
# file against discovery.json (every discovered component must appear, with
# a healthcheck), and against the self-contained/no-bind-mount contract S8
# built the image/compose generators around.
#
# The default flavor continues, byte-for-byte unchanged, below this block.
# ============================================================================
if [ "$FLAVOR" = "anvil-aggkit" ]; then
    DISCOVERY_JSON="$SNAPSHOT_DIR/discovery.json"

    if ! command -v jq &> /dev/null; then
        error "jq is required for --flavor anvil-aggkit"
        exit 1
    fi

    log ""
    log "=== [anvil-aggkit] Every service has a healthcheck ==="
    SERVICE_NAMES=$(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null || true)
    if [ -z "$SERVICE_NAMES" ]; then
        error "Could not list services from $COMPOSE_FILE (docker compose config --services failed)"
        ERRORS=$((ERRORS + 1))
    fi
    for service in $SERVICE_NAMES; do
        SERVICE_SECTION=$(sed -n "/^  ${service}:/,/^  [a-zA-Z]/p" "$COMPOSE_FILE")
        if echo "$SERVICE_SECTION" | grep -q "healthcheck:"; then
            log "✓ $service: has a healthcheck"
        else
            error "✗ $service: NO healthcheck defined -- required for every anvil-aggkit service"
            ERRORS=$((ERRORS + 1))
        fi
    done

    log ""
    log "=== [anvil-aggkit] Every discovered component is present in the compose file ==="
    if [ -f "$DISCOVERY_JSON" ]; then
        DISCOVERED_SERVICES=$(jq -r '
            [.l1_anvil, .agglayer, .aggkit_proxy, .haproxy, .dev_ui,
             (.l2_chains[]? | (.anvil, .aggkit, .aggkit_bridge))]
            | map(select(.found == true) | .service_name) | .[]
        ' "$DISCOVERY_JSON" 2>/dev/null || true)
        for svc in $DISCOVERED_SERVICES; do
            if echo "$SERVICE_NAMES" | grep -qx "$svc"; then
                log "✓ discovered component '$svc' present in compose"
            else
                error "✗ discovered component '$svc' is MISSING from the generated compose file"
                ERRORS=$((ERRORS + 1))
            fi
        done
    else
        warn "discovery.json not found at $DISCOVERY_JSON -- skipping the discovery cross-check"
        WARNINGS=$((WARNINGS + 1))
    fi

    log ""
    log "=== [anvil-aggkit] depends_on gates on service_healthy, not just service_started ==="
    # A `depends_on` list entry (or a map entry without condition:
    # service_healthy) starts a service as soon as its dependency's
    # CONTAINER starts, not once it is healthy -- exactly the ordering bug
    # this flavor's compose is supposed to avoid (anvil/agglayer/aggkit all
    # need their upstream truly ready first). `docker compose config
    # --format json` normalizes depends_on to the long map form regardless
    # of how it was written, so this is robust to either compose syntax.
    COMPOSE_JSON=$(docker compose -f "$COMPOSE_FILE" config --format json 2>/dev/null || true)
    if [ -z "$COMPOSE_JSON" ]; then
        error "docker compose config --format json failed for $COMPOSE_FILE"
        ERRORS=$((ERRORS + 1))
    else
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
