#!/bin/bash
set -euo pipefail

# Test script to verify a snapshot produces blocks
# Usage: ./test-snapshot.sh <snapshot-directory>

SNAPSHOT_DIR="${1:?Please provide snapshot directory}"

if [ ! -d "$SNAPSHOT_DIR" ]; then
  echo "Error: Directory $SNAPSHOT_DIR does not exist"
  exit 1
fi

echo "=== Testing Snapshot: $SNAPSHOT_DIR ==="
cd "$SNAPSHOT_DIR"

# Clean up any existing containers
echo "Cleaning up old containers..."
docker rm -f snapshot-init snapshot-geth snapshot-lighthouse-bn snapshot-lighthouse-vc 2>/dev/null || true
docker network prune -f >/dev/null 2>&1 || true

# Start snapshot
echo "Starting snapshot..."
docker-compose up -d

# Wait for initialization
echo "Waiting 20 seconds for initialization..."
sleep 20

# Check container status
echo -e "\n=== Container Status ==="
docker ps --filter name=snapshot- --format 'table {{.Names}}\t{{.Status}}'

# Check init exit code
echo -e "\n=== Init Container ==="
docker inspect snapshot-init --format='Exit Code: {{.State.ExitCode}}'

# Check if validator enabled
echo -e "\n=== Validator Enabled? ==="
if docker logs snapshot-lighthouse-vc 2>&1 | grep -q "Enabled validator"; then
  echo "✅ Validator enabled"
else
  echo "❌ Validator NOT enabled"
  docker logs snapshot-lighthouse-vc 2>&1 | tail -20
fi

# Check for published blocks
echo -e "\n=== Blocks Published? ==="
BLOCK_COUNT=$(docker logs snapshot-lighthouse-vc 2>&1 | grep -c "Successfully published block" || echo "0")
if [ "$BLOCK_COUNT" -gt 0 ]; then
  echo "✅ $BLOCK_COUNT blocks published"
  docker logs snapshot-lighthouse-vc 2>&1 | grep "Successfully published block" | tail -3
else
  echo "❌ No blocks published"
  echo "Validator logs:"
  docker logs snapshot-lighthouse-vc 2>&1 | tail -30
fi

# Monitor block progression
echo -e "\n=== Block Progression (10 seconds) ==="
for i in 1 2 3 4 5; do
  RESULT=$(docker exec snapshot-geth sh -c 'wget -qO- http://localhost:8545 --post-data='"'"'{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'"'"' --header='"'"'Content-Type: application/json'"'"' 2>/dev/null' || echo '{"result":"0x0"}')
  HEX=$(echo "$RESULT" | grep -o '0x[^"]*' || echo "0x0")
  DECIMAL=$((16#${HEX#0x}))
  echo "[$(date +%H:%M:%S)] Block: $HEX = $DECIMAL"
  sleep 2
done

# Final verdict
echo -e "\n=== VERDICT ==="
FINAL_BLOCK=$(docker exec snapshot-geth sh -c 'wget -qO- http://localhost:8545 --post-data='"'"'{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'"'"' --header='"'"'Content-Type: application/json'"'"' 2>/dev/null' | grep -o '0x[^"]*')
FINAL_DECIMAL=$((16#${FINAL_BLOCK#0x}))

if [ "$FINAL_DECIMAL" -gt 0 ]; then
  echo "✅ SNAPSHOT WORKS - Blocks are being produced (current: $FINAL_DECIMAL)"
  exit 0
else
  echo "❌ SNAPSHOT FAILED - No blocks produced"
  exit 1
fi
