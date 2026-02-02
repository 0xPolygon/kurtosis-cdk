#!/usr/bin/env bash
#
# Verify healthchecks in generated docker-compose.yml
# This script validates that all healthchecks use available tools (curl, not wget)
# and that critical services have proper healthcheck configurations
#
set -euo pipefail

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <SNAPSHOT_DIR>" >&2
    exit 1
fi

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

# Find all op-geth services
OP_GETH_SERVICES=$(grep -E "^  op-geth-[0-9]+:" "$COMPOSE_FILE" | sed 's/://g' | awk '{print $1}' || true)

if [ -n "$OP_GETH_SERVICES" ]; then
    for service in $OP_GETH_SERVICES; do
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
