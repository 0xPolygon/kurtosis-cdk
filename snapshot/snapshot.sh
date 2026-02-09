#!/bin/bash
set -euo pipefail

# Kurtosis CDK Snapshot Tool
# Creates a stateless snapshot from a running Kurtosis enclave
# Usage: ./snapshot.sh <enclave-name> [--out <output-dir>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENCLAVE_NAME=""
OUTPUT_DIR="./snapshots"
GETH_SVC="${GETH_SVC:-el-1-geth-lighthouse}"
PORT_ID="${PORT_ID:-rpc}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --out)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            ENCLAVE_NAME="$1"
            shift
            ;;
    esac
done

if [ -z "$ENCLAVE_NAME" ]; then
    echo "Usage: $0 <enclave-name> [--out <output-dir>]"
    echo ""
    echo "Environment variables:"
    echo "  GETH_SVC   - Geth service name (default: el-1-geth-lighthouse)"
    echo "  PORT_ID    - Port identifier (default: rpc)"
    exit 1
fi

echo "===== Kurtosis CDK Snapshot Creator ====="
echo "Enclave: $ENCLAVE_NAME"
echo "Output: $OUTPUT_DIR"
echo ""

# Build init container image
echo "Building init container image..."
if ! docker build -t kurtosis-cdk-snapshot-init:latest -f "$SCRIPT_DIR/Dockerfile.init" "$SCRIPT_DIR"; then
    echo "Error: Failed to build init container image"
    exit 1
fi
echo "✅ Init image built"
echo ""

# Check enclave exists
echo "Checking enclave..."
if ! kurtosis enclave inspect "$ENCLAVE_NAME" &>/dev/null; then
    echo "Error: Enclave '$ENCLAVE_NAME' not found"
    echo "Available enclaves:"
    kurtosis enclave ls
    exit 1
fi
echo "✅ Enclave found"
echo ""

# Discover geth RPC endpoint
echo "Discovering geth RPC endpoint..."
GETH_PORT_RAW=$(kurtosis port print "$ENCLAVE_NAME" "$GETH_SVC" "$PORT_ID" 2>/dev/null || true)
if [ -z "$GETH_PORT_RAW" ]; then
    echo "Error: Could not discover geth RPC endpoint"
    echo "Available services:"
    kurtosis enclave inspect "$ENCLAVE_NAME" | grep "Services:" -A 20
    echo ""
    echo "Hint: Set GETH_SVC and PORT_ID environment variables"
    exit 1
fi

# Add http:// prefix if not present
if [[ "$GETH_PORT_RAW" =~ ^http:// ]]; then
    GETH_PORT="$GETH_PORT_RAW"
else
    GETH_PORT="http://$GETH_PORT_RAW"
fi
echo "✅ Geth RPC: $GETH_PORT"
echo ""

# Extract chainId
echo "Extracting chainId..."
CHAIN_ID_HEX=$(cast rpc --rpc-url "$GETH_PORT" eth_chainId 2>/dev/null | sed 's/"//g' || echo "")
if [ -z "$CHAIN_ID_HEX" ]; then
    echo "Error: Failed to get chainId from geth"
    exit 1
fi
CHAIN_ID=$(printf "%d" "$CHAIN_ID_HEX")
echo "✅ Chain ID: $CHAIN_ID"
echo ""

# Get latest block number
echo "Getting latest block number..."
BLOCK_HEX=$(cast rpc --rpc-url "$GETH_PORT" eth_blockNumber 2>/dev/null | sed 's/"//g' || echo "")
if [ -z "$BLOCK_HEX" ]; then
    echo "Error: Failed to get block number from geth"
    exit 1
fi
BLOCK_NUMBER=$(printf "%d" "$BLOCK_HEX")
echo "✅ Latest block: $BLOCK_NUMBER (hex: $BLOCK_HEX)"
echo ""

# Create snapshot directory
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
SNAPSHOT_DIR="$OUTPUT_DIR/snapshot-$ENCLAVE_NAME-$TIMESTAMP"
mkdir -p "$SNAPSHOT_DIR"/{el,cl,val,tools,runtime}
echo "✅ Snapshot directory: $SNAPSHOT_DIR"
echo ""

# Dump state using debug_dumpBlock
echo "Dumping state via debug_dumpBlock (block $BLOCK_NUMBER)..."
echo "This may take several minutes for large state..."
# Convert block number to hex with 0x prefix for debug_dumpBlock
BLOCK_HEX_PARAM=$(printf "0x%x" "$BLOCK_NUMBER")
if ! cast rpc --rpc-url "$GETH_PORT" debug_dumpBlock "$BLOCK_HEX_PARAM" > "$SNAPSHOT_DIR/el/state_dump.json" 2>/dev/null; then
    echo "Error: debug_dumpBlock failed"
    echo ""
    echo "Common causes:"
    echo "  1. Debug namespace not enabled on geth"
    echo "     Solution: Add --http.api=eth,net,web3,debug to geth startup"
    echo "  2. Block number out of range"
    echo "     Solution: Check block number with: cast block-number --rpc-url $GETH_PORT"
    exit 1
fi
echo "✅ State dumped ($(stat -f%z "$SNAPSHOT_DIR/el/state_dump.json" 2>/dev/null || stat -c%s "$SNAPSHOT_DIR/el/state_dump.json") bytes)"
echo ""

# Convert to alloc format
echo "Converting to alloc format..."
if ! python3 "$SCRIPT_DIR/tools/dump_to_alloc.py" \
    "$SNAPSHOT_DIR/el/state_dump.json" \
    "$SNAPSHOT_DIR/el/alloc.json"; then
    echo "Error: Failed to convert state dump to alloc"
    exit 1
fi
echo ""

# Create genesis template
echo "Creating genesis template..."
if ! bash "$SCRIPT_DIR/scripts/create_genesis_template.sh" \
    "$SNAPSHOT_DIR/el/alloc.json" \
    "$SNAPSHOT_DIR/el/genesis.template.json" \
    "$CHAIN_ID"; then
    echo "Error: Failed to create genesis template"
    exit 1
fi
echo ""

# Test slot time configuration
echo "Testing slot time configuration..."
SLOT_TIME=2  # Default to 2s for better stability
if [ "${USE_1S_SLOTS:-}" = "true" ]; then
    echo "Attempting 1s slots (experimental)..."
    SLOT_TIME=1
fi
echo "Using SECONDS_PER_SLOT: $SLOT_TIME"
echo ""

# Create CL config from template
echo "Creating CL config..."
sed -e "s/SLOT_TIME_PLACEHOLDER/$SLOT_TIME/" \
    -e "s/CHAIN_ID_PLACEHOLDER/$CHAIN_ID/g" \
    "$SCRIPT_DIR/templates/config.yaml" > "$SNAPSHOT_DIR/cl/config.yaml"
echo "✅ CL config created"
echo ""

# Extract CL metadata files from enclave
echo "Extracting CL metadata files..."
TMP_GENESIS="/tmp/kurtosis-genesis-$$"
kurtosis files download "$ENCLAVE_NAME" el_cl_genesis_data "$TMP_GENESIS" >/dev/null 2>&1
if [ -f "$TMP_GENESIS/deposit_contract_block.txt" ]; then
    cp "$TMP_GENESIS/deposit_contract_block.txt" "$SNAPSHOT_DIR/cl/"
    cp "$TMP_GENESIS/deposit_contract_block_hash.txt" "$SNAPSHOT_DIR/cl/"
    cp "$TMP_GENESIS/deposit_contract.txt" "$SNAPSHOT_DIR/cl/"
    echo "✅ CL metadata files copied"
else
    echo "Warning: Could not extract CL metadata files from enclave"
fi
rm -rf "$TMP_GENESIS"
echo ""

# Copy validator mnemonics
echo "Copying validator mnemonics..."
cp "$SCRIPT_DIR/templates/mnemonics.yaml" "$SNAPSHOT_DIR/val/mnemonics.yaml"
echo "✅ Mnemonics copied"
echo ""

# Generate init script
echo "Generating init script..."
bash "$SCRIPT_DIR/scripts/create_init_script.sh" "$SNAPSHOT_DIR/tools/init.sh"
echo ""

# Generate docker-compose.yml
echo "Generating docker-compose.yml..."
bash "$SCRIPT_DIR/scripts/generate_compose.sh" "$SNAPSHOT_DIR"
echo ""

# Generate up.sh
echo "Generating up.sh..."
bash "$SCRIPT_DIR/scripts/create_up_script.sh" "$SNAPSHOT_DIR/up.sh"
echo ""

# Create metadata
echo "Creating metadata..."
cat > "$SNAPSHOT_DIR/metadata.json" <<EOF
{
  "enclave": "$ENCLAVE_NAME",
  "chainId": $CHAIN_ID,
  "block": $BLOCK_NUMBER,
  "timestamp": "$TIMESTAMP",
  "geth_rpc": "$GETH_PORT",
  "slot_time": $SLOT_TIME
}
EOF
echo "✅ Metadata created"
echo ""

# Create .gitignore for runtime directory
cat > "$SNAPSHOT_DIR/.gitignore" <<EOF
runtime/*
!runtime/.gitkeep
EOF
touch "$SNAPSHOT_DIR/runtime/.gitkeep"

echo "======================================"
echo "✅ Snapshot created successfully!"
echo ""
echo "Directory: $SNAPSHOT_DIR"
echo "  - el/genesis.template.json (with $CHAIN_ID accounts in alloc)"
echo "  - cl/config.yaml (${SLOT_TIME}s slots)"
echo "  - val/mnemonics.yaml"
echo "  - docker-compose.yml"
echo "  - tools/init.sh"
echo "  - up.sh"
echo ""
echo "To run the snapshot:"
echo "  cd $SNAPSHOT_DIR"
echo "  ./up.sh"
echo ""
echo "The snapshot will start with a FRESH genesis timestamp on every run!"
echo "======================================"
