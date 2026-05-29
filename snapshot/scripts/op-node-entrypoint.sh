#!/bin/sh
set -e

# Install jq (not included in op-node Alpine image)
apk add --no-cache jq > /dev/null 2>&1

echo "=== op-node entrypoint: patching rollup.json timestamps ==="

# Wait for op-geth to share genesis info
echo "Waiting for op-geth to provide L2 genesis info..."
MAX_WAIT=120
ELAPSED=0
while [ ! -f /shared/l2_genesis_time ] || [ ! -f /shared/l2_genesis_hash ]; do
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "ERROR: Timed out waiting for op-geth genesis info"
        exit 1
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# Small extra wait to ensure files are fully written
sleep 1

L2_GENESIS_TIME=$(cat /shared/l2_genesis_time)
L2_GENESIS_HASH=$(cat /shared/l2_genesis_hash)

echo "L2 genesis time: $L2_GENESIS_TIME"
echo "L2 genesis hash: $L2_GENESIS_HASH"

# Copy rollup.json to writable location and patch it
cp /rollup-ro/rollup.json /tmp/rollup.json

# Patch genesis.l2_time and genesis.l2.hash
if [ -n "$L2_GENESIS_HASH" ] && [ "$L2_GENESIS_HASH" != "" ]; then
    jq --argjson t "$L2_GENESIS_TIME" --arg h "$L2_GENESIS_HASH" \
        '.genesis.l2_time = $t | .genesis.l2.hash = $h' \
        /tmp/rollup.json > /tmp/rollup-patched.json
else
    echo "WARNING: No genesis hash available, only patching l2_time"
    jq --argjson t "$L2_GENESIS_TIME" \
        '.genesis.l2_time = $t' \
        /tmp/rollup.json > /tmp/rollup-patched.json
fi

mv /tmp/rollup-patched.json /tmp/rollup.json

# Patch L1 origin block hash (L1 blocks have different hashes after genesis time patching)
echo "Fetching actual L1 origin block hash..."
L1_BLOCK_NUM=$(jq -r '.genesis.l1.number' /tmp/rollup.json)
L1_BLOCK_HEX=$(printf '0x%x' "$L1_BLOCK_NUM")
echo "L1 origin block number: $L1_BLOCK_NUM ($L1_BLOCK_HEX)"

L1_ACTUAL_HASH=""
L1_WAIT=0
while [ $L1_WAIT -lt 60 ]; do
    RESP=$(wget -qO- --post-data="{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$L1_BLOCK_HEX\",false],\"id\":1}" --header="Content-Type: application/json" http://geth:8545 2>/dev/null || true)
    if [ -n "$RESP" ]; then
        L1_ACTUAL_HASH=$(echo "$RESP" | jq -r '.result.hash // empty')
        if [ -n "$L1_ACTUAL_HASH" ]; then
            break
        fi
    fi
    echo "Waiting for L1 geth to serve block $L1_BLOCK_NUM... ($L1_WAIT/60s)"
    sleep 2
    L1_WAIT=$((L1_WAIT + 2))
done

if [ -n "$L1_ACTUAL_HASH" ]; then
    echo "L1 origin hash: $L1_ACTUAL_HASH"
    jq --arg h "$L1_ACTUAL_HASH" '.genesis.l1.hash = $h' /tmp/rollup.json > /tmp/rollup-tmp.json && mv /tmp/rollup-tmp.json /tmp/rollup.json
else
    echo "WARNING: Could not fetch L1 origin block hash, proceeding with original"
fi

echo "Patched rollup.json:"
jq '.genesis' /tmp/rollup.json

echo "=== op-node entrypoint: starting op-node ==="

exec op-node \
    --rollup.config=/tmp/rollup.json \
    --l1=http://geth:8545 \
    --l1.beacon=http://beacon:4000 \
    --l2=http://"${OP_GETH_HOST:-op-geth-001}":8551 \
    --l2.jwt-secret=/jwt/jwtsecret \
    --rpc.addr=0.0.0.0 \
    --rpc.port=8547 \
    --rpc.enable-admin \
    --p2p.disable \
    --sequencer.enabled \
    --sequencer.l1-confs=0 \
    --rollup.l1-chain-config=/network-configs/l1-genesis.json \
    --metrics.enabled \
    --metrics.addr=0.0.0.0 \
    --metrics.port=7300
