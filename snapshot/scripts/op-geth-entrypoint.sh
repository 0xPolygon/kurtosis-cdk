#!/bin/sh
set -e

# Install jq (not included in op-geth Alpine image)
apk add --no-cache jq > /dev/null 2>&1

echo "=== op-geth entrypoint ==="

# If already initialized (container restart), skip patching and just start geth
if [ -d "/data/geth" ] && [ -f "/shared/l2_genesis_hash" ]; then
    echo "Already initialized, skipping genesis patching (container restart)"
    echo "Existing genesis hash: $(cat /shared/l2_genesis_hash)"
    echo "Existing genesis time: $(cat /shared/l2_genesis_time 2>/dev/null || echo unknown)"
    exec geth \
        --http \
        --http.addr=0.0.0.0 \
        --http.port=8545 \
        --http.vhosts='*' \
        --http.corsdomain='*' \
        --http.api=admin,engine,net,eth,web3,debug,txpool \
        --ws \
        --ws.addr=0.0.0.0 \
        --ws.port=8546 \
        --ws.origins='*' \
        --ws.api=admin,engine,net,eth,web3,debug,txpool \
        --authrpc.addr=0.0.0.0 \
        --authrpc.port=8551 \
        --authrpc.vhosts='*' \
        --authrpc.jwtsecret=/jwt/jwtsecret \
        --datadir=/data \
        --port=30303 \
        --discovery.port=30303 \
        --syncmode=full \
        --gcmode=archive \
        --metrics \
        --metrics.addr=0.0.0.0 \
        --metrics.port=9001 \
        --rollup.disabletxpoolgossip \
        --nodiscover
fi

echo "=== Patching L2 genesis timestamp ==="

# Copy genesis to writable location
cp /genesis-ro/l2-genesis.json /tmp/genesis.json

# Patch timestamp to current time (hex)
NOW=$(date +%s)
NOW_HEX=$(printf '0x%x' "$NOW")
echo "Patching L2 genesis timestamp to $NOW ($NOW_HEX)"

jq --arg ts "$NOW_HEX" '.timestamp = $ts' /tmp/genesis.json > /tmp/genesis-patched.json
mv /tmp/genesis-patched.json /tmp/genesis.json

# Write the patched timestamp for op-node to read
echo "$NOW" > /shared/l2_genesis_time

# Initialize geth
echo "Initializing op-geth with patched genesis..."
geth init --datadir=/data /tmp/genesis.json

# Extract genesis block hash by briefly starting geth with RPC
echo "Extracting genesis block hash..."
geth \
    --datadir=/data \
    --http --http.addr=127.0.0.1 --http.port=18545 --http.api=eth \
    --authrpc.addr=127.0.0.1 --authrpc.port=18551 --authrpc.jwtsecret=/jwt/jwtsecret \
    --nodiscover --rollup.disabletxpoolgossip \
    --port=0 --discovery.port=0 \
    2>/dev/null &
GETH_PID=$!

# Wait for RPC to be ready
RETRIES=0
while [ $RETRIES -lt 30 ]; do
    RESP=$(wget -qO- --post-data='{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' \
        --header="Content-Type: application/json" http://127.0.0.1:18545 2>/dev/null) && break
    RETRIES=$((RETRIES + 1))
    sleep 1
done
kill $GETH_PID 2>/dev/null || true
wait $GETH_PID 2>/dev/null || true

# Extract hash from response
GENESIS_HASH=$(echo "$RESP" | jq -r '.result.hash // empty')
if [ -n "$GENESIS_HASH" ]; then
    echo "L2 genesis block hash: $GENESIS_HASH"
    echo "$GENESIS_HASH" > /shared/l2_genesis_hash
else
    echo "ERROR: Could not extract genesis hash"
    echo "RPC response: $RESP"
    exit 1
fi

echo "=== op-geth entrypoint: starting geth ==="

exec geth \
    --http \
    --http.addr=0.0.0.0 \
    --http.port=8545 \
    --http.vhosts='*' \
    --http.corsdomain='*' \
    --http.api=admin,engine,net,eth,web3,debug,txpool \
    --ws \
    --ws.addr=0.0.0.0 \
    --ws.port=8546 \
    --ws.origins='*' \
    --ws.api=admin,engine,net,eth,web3,debug,txpool \
    --authrpc.addr=0.0.0.0 \
    --authrpc.port=8551 \
    --authrpc.vhosts='*' \
    --authrpc.jwtsecret=/jwt/jwtsecret \
    --datadir=/data \
    --port=30303 \
    --discovery.port=30303 \
    --syncmode=full \
    --gcmode=archive \
    --metrics \
    --metrics.addr=0.0.0.0 \
    --metrics.port=9001 \
    --rollup.disabletxpoolgossip \
    --nodiscover
