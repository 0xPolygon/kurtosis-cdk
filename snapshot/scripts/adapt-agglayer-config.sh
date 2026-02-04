#!/usr/bin/env bash
#
# Agglayer Config Adapter Script
# Adapts agglayer config.toml for docker-compose environment
#
# Usage: adapt-agglayer-config.sh <CONFIG_DIR>
#

set -euo pipefail

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <CONFIG_DIR>" >&2
    exit 1
fi

CONFIG_DIR="$1"
CONFIG_FILE="$CONFIG_DIR/config.toml"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Adapting agglayer config for docker-compose environment"
log "Config file: $CONFIG_FILE"

# Create a backup
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
log "Backup created: $CONFIG_FILE.bak"

# Perform adaptations using sed
log "Applying adaptations..."

# 1. Replace L1 node URLs: el-1-geth-lighthouse -> geth
sed -i 's|http://el-1-geth-lighthouse:8545|http://geth:8545|g' "$CONFIG_FILE"
sed -i 's|ws://el-1-geth-lighthouse:8546|ws://geth:8546|g' "$CONFIG_FILE"
log "  ✓ Updated L1 RPC endpoints to use 'geth' hostname"

# 2. Comment out L2 RPC if present (since L2 won't be in the snapshot by default)
# Find lines with cdk-erigon-rpc or similar L2 RPC endpoints and add a comment
sed -i 's|^\(\s*\)\([0-9]\+\s*=\s*"http://cdk-erigon-rpc\)|# NOTE: L2 RPC not included in snapshot - uncomment when L2 is available\n\1# \2|g' "$CONFIG_FILE"
log "  ✓ Commented out L2 RPC references (L2 not included in L1-only snapshot)"

# 3. Add gas price configuration for settlement
# This ensures settlement transactions have sufficient gas fees to be mined on L1
# The L1 geth default miner.gasprice is 1000000 wei, so we need at least that
if ! grep -q '\[outbound\.rpc\.settle\.gas-price\]' "$CONFIG_FILE"; then
    log "Adding gas price configuration to [outbound.rpc.settle]..."

    # Find the [outbound.rpc.settle] section and add gas-price config after it
    if grep -q '\[outbound\.rpc\.settle\]' "$CONFIG_FILE"; then
        # Add the gas-price subsection after the settle section settings
        sed -i '/^\[outbound\.rpc\.settle\]/,/^\[/ {
            /gas-multiplier-factor/a\
\
# Gas price configuration for settlement transactions\
# Ensures fees are high enough to be accepted by L1 miners\
[outbound.rpc.settle.gas-price]\
floor = "1gwei"        # 1 gwei minimum (L1 default miner.gasprice is 0.001 gwei)\
ceiling = "100gwei"    # 100 gwei maximum\
multiplier = 1000      # 1.0x multiplier (scaled by 1000)
        }' "$CONFIG_FILE"
        log "  ✓ Added gas price configuration with floor=1gwei"
    else
        log "  WARNING: [outbound.rpc.settle] section not found, skipping gas price config"
    fi
else
    log "  ✓ Gas price configuration already exists, skipping"
fi

# 4. Add a header comment explaining the adaptation
cat > "$CONFIG_FILE.tmp" << 'EOF'
# ============================================================================
# Agglayer Configuration - Adapted for Docker Compose Snapshot
# ============================================================================
# This configuration has been adapted from the Kurtosis enclave for use in
# a docker-compose environment. Key changes:
#
# - L1 RPC endpoints changed to use 'geth' hostname (from el-1-geth-lighthouse)
# - L2 RPC endpoints commented out (L2 stack not included in L1-only snapshot)
# - Gas price floor configured (1 gwei minimum to ensure L1 miners accept txs)
# - All contract addresses and keys preserved from original deployment
#
# To use with L2:
# 1. Deploy L2 services (cdk-erigon-rpc or equivalent)
# 2. Uncomment the L2 RPC lines in [full-node-rpcs] section
# 3. Update the hostname to match your L2 service name
# ============================================================================

EOF

cat "$CONFIG_FILE" >> "$CONFIG_FILE.tmp"
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

log "Adaptation complete!"
log "Original config backed up to: $CONFIG_FILE.bak"

# Show a summary of key config values
log ""
log "Configuration summary:"
log "  L1 node URL: $(grep 'node-url.*=' "$CONFIG_FILE" | head -1 | sed 's/^.*= *//')"
log "  L1 WS URL: $(grep 'ws-node-url.*=' "$CONFIG_FILE" | head -1 | sed 's/^.*= *//')"
log "  Rollup Manager: $(grep 'rollup-manager-contract.*=' "$CONFIG_FILE" | head -1 | sed 's/^.*= *//')"
log "  GER Contract: $(grep 'polygon-zkevm-global-exit-root-v2-contract.*=' "$CONFIG_FILE" | head -1 | sed 's/^.*= *//')"

# Check if gas price floor was added
GAS_FLOOR=$(grep -A5 '\[outbound\.rpc\.settle\.gas-price\]' "$CONFIG_FILE" | grep '^floor' | sed 's/^.*= *//' | sed 's/ *#.*//' | tr -d '"' || echo "not set")
if [ "$GAS_FLOOR" != "not set" ]; then
    log "  Gas price floor: $GAS_FLOOR"
fi

exit 0
