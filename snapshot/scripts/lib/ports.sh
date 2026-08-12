#!/usr/bin/env bash
#
# Host-port numbering for generated snapshot bundles.
#
# SINGLE SOURCE OF TRUTH. The per-L2 port arithmetic used to be copy-pasted in
# three places (generate-compose.sh twice, generate-summary.sh once), which is
# exactly how a compose file and its summary.json drift apart. Every consumer
# must call the helpers below instead of open-coding `10000 + N*1000 + off`.
#
# Per-L2 ports:  SNAPSHOT_L2_PORT_BASE + <prefix as decimal> * SNAPSHOT_L2_PORT_STRIDE + <offset>
#   prefix 001 -> 11xxx, prefix 002 -> 12xxx
#
# Fixed (single-instance) ports live in SNAPSHOT_FIXED_PORTS.
#
# Every port is env-overridable in the generated compose file; the environment
# variable names are produced by snapshot_l2_port_env / snapshot_fixed_port_env
# so that the compose file, the summary and the docs cannot disagree.
#
# Usage:
#   source "$(dirname "$0")/lib/ports.sh"
#   port=$(snapshot_l2_port 001 http)                 # -> 11545
#   expr=$(snapshot_l2_port_expr 001 http)            # -> ${L2_001_HTTP_PORT:-11545}
#   port=$(snapshot_fixed_port devnet_proxy)          # -> 8555
#   expr=$(snapshot_fixed_port_expr devnet_proxy)     # -> ${DEVNET_PROXY_PORT:-8555}
#

# Idempotent source guard (this file is sourced by several scripts that may in
# turn source each other).
if [ -n "${_SNAPSHOT_LIB_PORTS_SOURCED:-}" ]; then
    # shellcheck disable=SC2317 # the `exit 0` fallback only runs when this file is executed directly, not sourced
    return 0 2>/dev/null || exit 0
fi
_SNAPSHOT_LIB_PORTS_SOURCED=1

SNAPSHOT_L2_PORT_BASE=10000
SNAPSHOT_L2_PORT_STRIDE=1000

# Per-L2 service key -> offset inside that L2's 1000-port block.
#
# The first seven entries are the historical (default/geth+op-reth flavor)
# offsets and MUST keep their values: changing one silently repoints an
# already-published bundle's documented ports.
#   http           execution-layer JSON-RPC (op-reth, and the anvil L2s)
#   ws             execution-layer websocket (op-reth only)
#   engine         engine API (op-reth only)
#   node_rpc       op-node RPC
#   node_metrics   op-node metrics
#   aggkit_rpc     aggkit JSON-RPC (5576)
#   aggkit_rest    aggkit bridge REST API (5577)
# anvil-aggkit flavor addition:
#   aggkit_bridge_rpc  the `-bridge` sibling's JSON-RPC (also 5576 in-container,
#                      so it needs its own host port next to aggkit_rpc)
declare -gA SNAPSHOT_L2_PORT_OFFSETS=(
    [http]=545
    [ws]=546
    [engine]=551
    [node_rpc]=547
    [node_metrics]=300
    [aggkit_rpc]=576
    [aggkit_rest]=577
    [aggkit_bridge_rpc]=586
)

# Single-instance services. Values are the plan's §2 component/port map.
declare -gA SNAPSHOT_FIXED_PORTS=(
    [l1_rpc]=8545
    [agglayer_grpc]=4443
    [agglayer_readrpc]=4444
    [agglayer_admin]=4446
    [agglayer_metrics]=9092
    [devnet_proxy]=8555
    [aggkit_proxy]=8556
    [dev_ui]=8557
)

# Environment variable names used to override the fixed ports.
declare -gA SNAPSHOT_FIXED_PORT_ENV=(
    [l1_rpc]=L1_RPC_PORT
    [agglayer_grpc]=AGGLAYER_GRPC_PORT
    [agglayer_readrpc]=AGGLAYER_READRPC_PORT
    [agglayer_admin]=AGGLAYER_ADMIN_PORT
    [agglayer_metrics]=AGGLAYER_METRICS_PORT
    [devnet_proxy]=DEVNET_PROXY_PORT
    [aggkit_proxy]=AGGKIT_PROXY_PORT
    [dev_ui]=DEVUI_PORT
)

# snapshot_l2_port <prefix> <key>
# Echo the host port for service <key> of L2 network <prefix> (e.g. "001").
snapshot_l2_port() {
    local prefix="$1" key="$2" offset
    offset="${SNAPSHOT_L2_PORT_OFFSETS[$key]:-}"
    if [ -z "$offset" ]; then
        echo "ports.sh: unknown L2 port key '$key'" >&2
        return 1
    fi
    local port=$((SNAPSHOT_L2_PORT_BASE + 10#$prefix * SNAPSHOT_L2_PORT_STRIDE + offset))
    # The formula runs out of TCP port space at prefix 055 (65545). Fail loudly
    # rather than emit an invalid port that only surfaces as a confusing
    # `docker compose up` error.
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "ports.sh: computed host port $port for L2 prefix '$prefix' key '$key' is outside 1-65535" >&2
        return 1
    fi
    echo "$port"
}

# snapshot_l2_port_env <prefix> <key>
# Echo the override environment variable name, e.g. L2_001_HTTP_PORT.
snapshot_l2_port_env() {
    local prefix="$1" key="$2"
    if [ -z "${SNAPSHOT_L2_PORT_OFFSETS[$key]:-}" ]; then
        echo "ports.sh: unknown L2 port key '$key'" >&2
        return 1
    fi
    echo "L2_${prefix}_${key^^}_PORT"
}

# snapshot_l2_port_expr <prefix> <key>
# Echo a compose-interpolation expression: ${L2_001_HTTP_PORT:-11545}
snapshot_l2_port_expr() {
    local prefix="$1" key="$2" name port
    name=$(snapshot_l2_port_env "$prefix" "$key") || return 1
    port=$(snapshot_l2_port "$prefix" "$key") || return 1
    # shellcheck disable=SC2016 # literal ${VAR:-default} compose-interpolation syntax, not shell expansion
    printf '${%s:-%s}' "$name" "$port"
}

# snapshot_fixed_port <key>
snapshot_fixed_port() {
    local key="$1" port
    port="${SNAPSHOT_FIXED_PORTS[$key]:-}"
    if [ -z "$port" ]; then
        echo "ports.sh: unknown fixed port key '$key'" >&2
        return 1
    fi
    echo "$port"
}

# snapshot_fixed_port_env <key>
snapshot_fixed_port_env() {
    local key="$1" name
    name="${SNAPSHOT_FIXED_PORT_ENV[$key]:-}"
    if [ -z "$name" ]; then
        echo "ports.sh: unknown fixed port key '$key'" >&2
        return 1
    fi
    echo "$name"
}

# snapshot_fixed_port_expr <key>
# Echo a compose-interpolation expression: ${DEVNET_PROXY_PORT:-8555}
snapshot_fixed_port_expr() {
    local key="$1" name port
    name=$(snapshot_fixed_port_env "$key") || return 1
    port=$(snapshot_fixed_port "$key") || return 1
    # shellcheck disable=SC2016 # literal ${VAR:-default} compose-interpolation syntax, not shell expansion
    printf '${%s:-%s}' "$name" "$port"
}
