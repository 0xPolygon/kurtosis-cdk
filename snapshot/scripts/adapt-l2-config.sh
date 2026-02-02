#!/usr/bin/env bash
#
# L2 Config Adapter Script
# Adapts L2 configuration files for docker-compose environment
#
# Usage: adapt-l2-config.sh <CONFIG_DIR> <NETWORK_PREFIX>
#

set -euo pipefail

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <CONFIG_DIR> <NETWORK_PREFIX>" >&2
    exit 1
fi

CONFIG_DIR="$1"
NETWORK_PREFIX="$2"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Adapting L2 configs for network $NETWORK_PREFIX"
log "Config directory: $CONFIG_DIR"

# ============================================================================
# Adapt aggkit configuration (if present)
# ============================================================================

AGGKIT_CONFIG="$CONFIG_DIR/aggkit-config.toml"

if [ -f "$AGGKIT_CONFIG" ]; then
    log "Adapting aggkit config..."

    # Create a backup
    cp "$AGGKIT_CONFIG" "$AGGKIT_CONFIG.bak"
    log "  Backup created: aggkit-config.toml.bak"

    # Perform adaptations using sed
    log "  Applying adaptations..."

    # 1. Replace L1 node URLs: el-1-geth-lighthouse -> geth (snapshot's L1)
    sed -i 's|http://el-1-geth-lighthouse:[0-9]\+|http://geth:8545|g' "$AGGKIT_CONFIG"
    sed -i 's|ws://el-1-geth-lighthouse:[0-9]\+|ws://geth:8546|g' "$AGGKIT_CONFIG"
    log "    ✓ Updated L1 RPC endpoints to use 'geth' hostname"

    # 2. Replace L2 RPC URLs with docker-compose service names
    # Pattern: op-el-1-op-geth-op-node-001 -> op-geth-001
    # Pattern: op-el-2-op-geth-op-node-001 -> op-geth-rpc-001 (if RPC node exists)
    sed -i "s|http://op-el-[0-9]\+-op-geth-op-node-$NETWORK_PREFIX:[0-9]\+|http://op-geth-$NETWORK_PREFIX:8545|g" "$AGGKIT_CONFIG"
    sed -i "s|ws://op-el-[0-9]\+-op-geth-op-node-$NETWORK_PREFIX:[0-9]\+|ws://op-geth-$NETWORK_PREFIX:8546|g" "$AGGKIT_CONFIG"
    log "    ✓ Updated L2 RPC endpoints to use 'op-geth-$NETWORK_PREFIX' hostname"

    # 3. Replace op-node URLs
    # Pattern: op-cl-1-op-node-op-geth-001 -> op-node-001
    sed -i "s|http://op-cl-[0-9]\+-op-node-op-geth-$NETWORK_PREFIX:[0-9]\+|http://op-node-$NETWORK_PREFIX:8547|g" "$AGGKIT_CONFIG"
    log "    ✓ Updated op-node endpoints to use 'op-node-$NETWORK_PREFIX' hostname"

    # 4. Add a header comment explaining the adaptation
    cat > "$AGGKIT_CONFIG.tmp" << EOF
# ============================================================================
# AggKit Configuration for L2 Network $NETWORK_PREFIX - Adapted for Docker Compose Snapshot
# ============================================================================
# This configuration has been adapted from the Kurtosis enclave for use in
# a docker-compose environment. Key changes:
#
# - L1 RPC endpoints changed to use 'geth' hostname (snapshot's L1)
# - L2 RPC endpoints changed to use 'op-geth-$NETWORK_PREFIX' hostname
# - op-node endpoints changed to use 'op-node-$NETWORK_PREFIX' hostname
# - All contract addresses and keys preserved from original deployment
#
# Service names:
# - L1 Geth: geth (from snapshot)
# - L2 op-geth: op-geth-$NETWORK_PREFIX
# - L2 op-node: op-node-$NETWORK_PREFIX
# ============================================================================

EOF

    cat "$AGGKIT_CONFIG" >> "$AGGKIT_CONFIG.tmp"
    mv "$AGGKIT_CONFIG.tmp" "$AGGKIT_CONFIG"

    log "  ✓ aggkit config adapted successfully"
    log "  Original backed up to: aggkit-config.toml.bak"
else
    log "  No aggkit config found (optional)"
fi

# ============================================================================
# Validate critical files
# ============================================================================

log "Validating L2 configuration files..."

CRITICAL_FILES=(
    "rollup.json"
    "jwt.hex"
)

MISSING_FILES=()
for file in "${CRITICAL_FILES[@]}"; do
    if [ ! -f "$CONFIG_DIR/$file" ]; then
        MISSING_FILES+=("$file")
    else
        log "  ✓ $file present"
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    log "  WARNING: Missing critical files: ${MISSING_FILES[*]}"
    log "  L2 network may not function properly"
else
    log "  ✓ All critical files present"
fi

# ============================================================================
# Summary
# ============================================================================

log ""
log "L2 configuration adaptation complete for network $NETWORK_PREFIX"
log "Files in config directory:"
ls -lh "$CONFIG_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'

exit 0
