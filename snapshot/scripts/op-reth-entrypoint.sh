#!/bin/sh
set -e

# ============================================================================
# op-reth L2 execution-layer entrypoint (snapshot restore).
#
# Mirrors op-geth-entrypoint.sh but drives the op-reth (Reth-based OP EL)
# binary instead of geth. Used when the restored L2 EL image is op-reth
# (e.g. the FEP / op-succinct topology) rather than op-geth.
#
# Responsibilities (identical handshake to op-geth-entrypoint.sh):
#   1. Patch the L2 genesis `timestamp` to L1-origin-block-timestamp + 1
#      (the snapshot re-anchors L1 genesis time on every restore).
#   2. Initialise the reth DB from the patched genesis.
#   3. Extract the L2 genesis block hash and publish it (with the genesis
#      time) on the shared volume so op-node-entrypoint.sh can patch
#      rollup.json (genesis.l2.hash / genesis.l2_time).
#   4. Start op-reth as the sequencer EL serving HTTP/WS/engine RPC.
#
# The op-reth image (Ubuntu-based) ships without jq/wget; install them at
# startup, matching how op-geth-entrypoint.sh does `apk add jq`.
# ============================================================================

echo "=== op-reth entrypoint ==="

# Install jq + wget (not included in the op-reth image; Ubuntu/Debian base).
if ! command -v jq > /dev/null 2>&1 || ! command -v wget > /dev/null 2>&1; then
    echo "Installing jq + wget..."
    apt-get update > /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends jq wget ca-certificates > /dev/null 2>&1
fi

DATADIR=/data
GENESIS_RO=/genesis-ro/l2-genesis.json
ROLLUP_RO=/rollup-ro/rollup.json
GENESIS=/tmp/genesis.json

# Reth lays its DB down under <datadir>/db; treat its presence as "initialized".
if [ -d "$DATADIR/db" ] && [ -f "/shared/l2_genesis_hash" ]; then
    echo "Already initialized, skipping genesis patching (container restart)"
    echo "Existing genesis hash: $(cat /shared/l2_genesis_hash)"
    echo "Existing genesis time: $(cat /shared/l2_genesis_time 2>/dev/null || echo unknown)"
    exec op-reth node \
        --chain="$GENESIS" \
        --datadir="$DATADIR" \
        --http \
        --http.addr=0.0.0.0 \
        --http.port=8545 \
        --http.api=admin,net,eth,web3,debug,txpool,miner \
        --http.corsdomain='*' \
        --ws \
        --ws.addr=0.0.0.0 \
        --ws.port=8546 \
        --ws.origins='*' \
        --ws.api=admin,net,eth,web3,debug,txpool,miner \
        --authrpc.addr=0.0.0.0 \
        --authrpc.port=8551 \
        --authrpc.jwtsecret=/jwt/jwtsecret \
        --port=30303 \
        --metrics=0.0.0.0:9001 \
        --rollup.disable-tx-pool-gossip \
        --disable-discovery
fi

echo "=== Patching L2 genesis timestamp ==="

# Copy genesis to writable location
cp "$GENESIS_RO" "$GENESIS"

# Read L1 origin block number from rollup.json
L1_BLOCK_NUM=$(jq -r '.genesis.l1.number' "$ROLLUP_RO")
L1_BLOCK_HEX=$(printf '0x%x' "$L1_BLOCK_NUM")
echo "L1 origin block number: $L1_BLOCK_NUM ($L1_BLOCK_HEX)"

# Wait for L1 geth to serve the origin block and get its timestamp
echo "Waiting for L1 geth to be available..."
L1_ORIGIN_TIMESTAMP=""
L1_WAIT=0
while [ $L1_WAIT -lt 120 ]; do
    RESP=$(wget -qO- --post-data="{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$L1_BLOCK_HEX\",false],\"id\":1}" --header="Content-Type: application/json" http://geth:8545 2>/dev/null || true)
    if [ -n "$RESP" ]; then
        L1_ORIGIN_TIMESTAMP=$(echo "$RESP" | jq -r '.result.timestamp // empty')
        if [ -n "$L1_ORIGIN_TIMESTAMP" ]; then
            break
        fi
    fi
    echo "Waiting for L1 geth to serve block $L1_BLOCK_NUM... ($L1_WAIT/120s)"
    sleep 2
    L1_WAIT=$((L1_WAIT + 2))
done

if [ -z "$L1_ORIGIN_TIMESTAMP" ]; then
    echo "ERROR: Could not fetch L1 origin block timestamp after 120s"
    exit 1
fi

# Convert hex timestamp to decimal and add 1
L1_ORIGIN_TS_DEC=$(printf '%d' "$L1_ORIGIN_TIMESTAMP")
NOW=$((L1_ORIGIN_TS_DEC + 1))
NOW_HEX=$(printf '0x%x' "$NOW")
echo "L1 origin timestamp: $L1_ORIGIN_TS_DEC, setting L2 genesis timestamp to $NOW ($NOW_HEX)"

jq --arg ts "$NOW_HEX" '.timestamp = $ts' "$GENESIS" > /tmp/genesis-patched.json
mv /tmp/genesis-patched.json "$GENESIS"

# Write the patched timestamp for op-node to read
echo "$NOW" > /shared/l2_genesis_time

# Initialize reth from the patched genesis
echo "Initializing op-reth with patched genesis..."
op-reth init --chain="$GENESIS" --datadir="$DATADIR"

# Extract genesis block hash by briefly starting op-reth with RPC
echo "Extracting genesis block hash..."
op-reth node \
    --chain="$GENESIS" \
    --datadir="$DATADIR" \
    --http --http.addr=127.0.0.1 --http.port=18545 --http.api=eth \
    --authrpc.addr=127.0.0.1 --authrpc.port=18551 --authrpc.jwtsecret=/jwt/jwtsecret \
    --disable-discovery --rollup.disable-tx-pool-gossip \
    --port=0 \
    > /tmp/reth-init.log 2>&1 &
RETH_PID=$!

# Wait for RPC to be ready and fetch genesis block hash
GENESIS_HASH=""
RETRIES=0
while [ $RETRIES -lt 60 ]; do
    RESP=$(wget -qO- --post-data='{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' \
        --header="Content-Type: application/json" http://127.0.0.1:18545 2>/dev/null || true)
    if [ -n "$RESP" ]; then
        GENESIS_HASH=$(echo "$RESP" | jq -r '.result.hash // empty')
        if [ -n "$GENESIS_HASH" ]; then
            break
        fi
    fi
    RETRIES=$((RETRIES + 1))
    sleep 1
done
kill $RETH_PID 2>/dev/null || true
wait $RETH_PID 2>/dev/null || true

if [ -n "$GENESIS_HASH" ]; then
    echo "L2 genesis block hash: $GENESIS_HASH"
    echo "$GENESIS_HASH" > /shared/l2_genesis_hash
else
    echo "ERROR: Could not extract genesis hash"
    echo "RPC response: $RESP"
    echo "--- reth init log (tail) ---"
    tail -50 /tmp/reth-init.log || true
    exit 1
fi

echo "=== op-reth entrypoint: starting op-reth ==="

# NOTE: `miner` is included in --http.api / --ws.api so op-batcher v1.16.9 can
# call miner_setMaxDASize (DA throttling) at startup. Without it the batcher
# hits a critical RPC error and shuts down -> the restored L2 safe head sticks at
# genesis and never finalizes. Mirrors the op-geth-entrypoint.sh miner fix.
exec op-reth node \
    --chain="$GENESIS" \
    --datadir="$DATADIR" \
    --http \
    --http.addr=0.0.0.0 \
    --http.port=8545 \
    --http.api=admin,net,eth,web3,debug,txpool,miner \
    --http.corsdomain='*' \
    --ws \
    --ws.addr=0.0.0.0 \
    --ws.port=8546 \
    --ws.origins='*' \
    --ws.api=admin,net,eth,web3,debug,txpool,miner \
    --authrpc.addr=0.0.0.0 \
    --authrpc.port=8551 \
    --authrpc.jwtsecret=/jwt/jwtsecret \
    --port=30303 \
    --metrics=0.0.0.0:9001 \
    --rollup.disable-tx-pool-gossip \
    --disable-discovery
