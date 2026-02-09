#!/bin/bash
set -euo pipefail

# Create EL genesis template with alloc injected
# Usage: create_genesis_template.sh <alloc.json> <output_template.json> <chain_id>

ALLOC_FILE="$1"
OUTPUT_FILE="$2"
CHAIN_ID="$3"

echo "Creating genesis template with chainId=$CHAIN_ID..."

# Create base genesis template
cat > "$OUTPUT_FILE" <<EOF
{
  "config": {
    "chainId": $CHAIN_ID,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "muirGlacierBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "arrowGlacierBlock": 0,
    "grayGlacierBlock": 0,
    "mergeNetsplitBlock": 0,
    "shanghaiTime": 0,
    "cancunTime": 0,
    "blobSchedule": {
      "cancun": {
        "target": 3,
        "max": 6,
        "baseFeeUpdateFraction": 3338477
      }
    },
    "terminalTotalDifficulty": 0,
    "terminalTotalDifficultyPassed": true
  },
  "nonce": "0x0",
  "timestamp": "TIMESTAMP_PLACEHOLDER",
  "extraData": "0x",
  "gasLimit": "0x1c9c380",
  "difficulty": "0x1",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "0x0000000000000000000000000000000000000000",
  "alloc": {},
  "number": "0x0",
  "gasUsed": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "baseFeePerGas": "0x3b9aca00"
}
EOF

# Inject alloc using jq
if [ -f "$ALLOC_FILE" ]; then
    echo "Injecting alloc with $(jq 'length' "$ALLOC_FILE") accounts..."
    jq --slurpfile alloc "$ALLOC_FILE" '.alloc = $alloc[0]' "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp"
    mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
else
    echo "Warning: alloc file not found, using empty alloc"
fi

echo "Genesis template created: $OUTPUT_FILE"
