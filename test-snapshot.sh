#!/bin/bash
set -e

SNAPSHOT_DIR="$1"
if [ -z "$SNAPSHOT_DIR" ]; then
  echo "Usage: $0 <snapshot-directory>"
  exit 1
fi

cd "$SNAPSHOT_DIR"

echo "=== Testing Snapshot Configuration ==="
echo ""

echo "1. Checking aggkit image..."
IMG=$(grep "image.*aggkit" docker-compose.yml | head -1 | grep -o "aggkit:[a-z]*" || echo "NOT FOUND")
if [[ "$IMG" == "aggkit:local" ]]; then
  echo "✅ Using aggkit:local"
else
  echo "❌ Wrong image: $IMG"
fi
echo ""

echo "2. Checking block numbers in config..."
INIT_BLOCK=$(grep "InitialBlock" aggkit/config.toml | head -1 | grep -o '"[0-9]*"' || echo "NOT FOUND")
if [[ "$INIT_BLOCK" == '"0"' ]]; then
  echo "✅ InitialBlock = $INIT_BLOCK"
else
  echo "❌ InitialBlock = $INIT_BLOCK (should be \"0\")"
fi
echo ""

echo "3. Checking deployed contract addresses..."
if [ -s aggkit/deployed_contracts.json ] && [ "$(cat aggkit/deployed_contracts.json)" != "{}" ]; then
  echo "✅ Contract addresses extracted:"
  cat aggkit/deployed_contracts.json | jq '{AgglayerGER, AgglayerManager, AgglayerBridge}' 2>/dev/null
else
  echo "❌ No contract addresses found (empty or missing file)"
fi
echo ""

echo "4. Checking config uses actual addresses..."
CONFIG_GER=$(grep "polygonZkEVMGlobalExitRootAddress" aggkit/config.toml | head -1 | grep -o '0x[a-fA-F0-9]*' || echo "NOT FOUND")
DEPLOYED_GER=$(cat aggkit/deployed_contracts.json | jq -r '.AgglayerGER // .polygonZkEVMGlobalExitRootAddress // "NOT FOUND"' 2>/dev/null)

if [[ "$CONFIG_GER" != "NOT FOUND" ]] && [[ "$DEPLOYED_GER" != "NOT FOUND" ]] && [[ "$(echo $CONFIG_GER | tr '[:upper:]' '[:lower:]')" == "$(echo $DEPLOYED_GER | tr '[:upper:]' '[:lower:]')" ]]; then
  echo "✅ Config and deployed addresses match: $CONFIG_GER"
else
  echo "❌ Address mismatch:"
  echo "   Config: $CONFIG_GER"
  echo "   Deployed: $DEPLOYED_GER"
fi
echo ""

echo "5. Checking contract in genesis..."
if [ -f runtime/el_genesis.json ]; then
  GER_LOWER=$(echo "$DEPLOYED_GER" | tr '[:upper:]' '[:lower:]')
  HAS_CODE=$(jq ".alloc.\"$GER_LOWER\" | has(\"code\")" runtime/el_genesis.json 2>/dev/null || echo "false")
  if [ "$HAS_CODE" = "true" ]; then
    CODE_LEN=$(jq -r ".alloc.\"$GER_LOWER\".code | length" runtime/el_genesis.json 2>/dev/null)
    echo "✅ GlobalExitRoot ($GER_LOWER) has code in genesis ($CODE_LEN bytes)"
  else
    echo "❌ GlobalExitRoot ($GER_LOWER) has NO CODE in genesis"
  fi
else
  echo "⚠️  runtime/el_genesis.json not found (run ./up.sh first)"
fi
echo ""

echo "================================================"
echo "Summary: Snapshot configuration check complete!"
echo "================================================"
