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

# Verify critical contracts exist (if sovereign rollup is detected)
echo "Checking for deployed contracts..."
CONTRACTS_SVC="contracts-001"
CONTRACT_WARNING=false
if kurtosis service inspect "$ENCLAVE_NAME" "$CONTRACTS_SVC" &>/dev/null; then
    # Extract deployed_contracts.json to get contract addresses
    TMP_CONTRACTS="/tmp/kurtosis-contracts-$$"
    timeout 10 kurtosis service exec "$ENCLAVE_NAME" "$CONTRACTS_SVC" "cat /opt/deployed_contracts.json" > "$TMP_CONTRACTS" 2>/dev/null || echo "{}" > "$TMP_CONTRACTS"

    # Check GlobalExitRoot (required by aggkit)
    GLOBAL_EXIT_ROOT_ADDR=$(jq -r '.polygonZkEVMGlobalExitRootAddress // .AgglayerGER // empty' "$TMP_CONTRACTS" 2>/dev/null || echo "")
    if [ -n "$GLOBAL_EXIT_ROOT_ADDR" ]; then
        echo "  Found GlobalExitRoot address in config: $GLOBAL_EXIT_ROOT_ADDR"
        # Verify the contract has code on L1
        CODE_CHECK=$(cast code --rpc-url "$GETH_PORT" "$GLOBAL_EXIT_ROOT_ADDR" 2>/dev/null || echo "0x")
        if [ "$CODE_CHECK" = "0x" ] || [ -z "$CODE_CHECK" ]; then
            echo "  ⚠️  ERROR: GlobalExitRoot contract has NO CODE at $GLOBAL_EXIT_ROOT_ADDR"
            echo "  This will cause aggkit to fail with 'no contract code at given address'"
            echo "  "
            echo "  Possible causes:"
            echo "    1. Snapshot taken too early - contracts not deployed yet"
            echo "    2. Contracts deployment failed"
            echo "    3. Wrong L1 RPC URL"
            echo "  "
            echo "  Please ensure contracts are fully deployed before taking snapshot."
            CONTRACT_WARNING=true
        else
            CODE_SIZE=${#CODE_CHECK}
            echo "  ✅ GlobalExitRoot has code ($CODE_SIZE bytes)"
        fi
    else
        echo "  ⚠️  WARNING: Could not find GlobalExitRoot address in deployed_contracts.json"
    fi

    # Check RollupManager
    ROLLUP_MANAGER_ADDR=$(jq -r '.polygonRollupManagerAddress // .AgglayerManager // empty' "$TMP_CONTRACTS" 2>/dev/null || echo "")
    if [ -n "$ROLLUP_MANAGER_ADDR" ]; then
        CODE_CHECK=$(cast code --rpc-url "$GETH_PORT" "$ROLLUP_MANAGER_ADDR" 2>/dev/null || echo "0x")
        if [ "$CODE_CHECK" = "0x" ] || [ -z "$CODE_CHECK" ]; then
            echo "  ⚠️  ERROR: RollupManager contract has NO CODE at $ROLLUP_MANAGER_ADDR"
            CONTRACT_WARNING=true
        else
            echo "  ✅ RollupManager has code"
        fi
    fi

    rm -f "$TMP_CONTRACTS"

    if [ "$CONTRACT_WARNING" = true ]; then
        echo ""
        echo "❌ SNAPSHOT ABORTED: Critical contracts missing code"
        echo "   Wait for contracts to be deployed before taking snapshot."
        echo "   You can check contract deployment logs with:"
        echo "     kurtosis service logs $ENCLAVE_NAME $CONTRACTS_SVC"
        exit 1
    fi
else
    echo "  No contracts service found - skipping contract verification"
fi
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

# Inject critical contracts that debug_dumpBlock might have missed
echo "Injecting critical contracts into alloc..."
CONTRACTS_SVC="contracts-001"
if kurtosis service inspect "$ENCLAVE_NAME" "$CONTRACTS_SVC" &>/dev/null; then
    TMP_CONTRACTS="/tmp/kurtosis-contracts-inject-$$"

    # Try to get deployed contracts
    for contracts_file in "/opt/agglayer-contracts/deployment/v2/deploy_output.json" "/opt/combined.json" "/opt/deploy_output.json" "/opt/deployed_contracts.json"; do
        if timeout 5 kurtosis service exec "$ENCLAVE_NAME" contracts-001 "cat $contracts_file" > "$TMP_CONTRACTS" 2>/dev/null; then
            if [ -s "$TMP_CONTRACTS" ] && jq empty "$TMP_CONTRACTS" 2>/dev/null; then
                # Extract contract addresses
                GER_ADDR=$(jq -r '.polygonZkEVMGlobalExitRootAddress // .AgglayerGER // empty' "$TMP_CONTRACTS" 2>/dev/null)
                ROLLUP_MANAGER_ADDR=$(jq -r '.polygonRollupManagerAddress // .AgglayerManager // empty' "$TMP_CONTRACTS" 2>/dev/null)
                BRIDGE_ADDR=$(jq -r '.polygonZkEVMBridgeAddress // .AgglayerBridge // empty' "$TMP_CONTRACTS" 2>/dev/null)
                ROLLUP_ADDR=$(jq -r '.rollupAddress // .polygonZkEVMAddress // empty' "$TMP_CONTRACTS" 2>/dev/null)

                # Inject each contract into alloc if missing
                for addr_var in GER_ADDR ROLLUP_MANAGER_ADDR BRIDGE_ADDR ROLLUP_ADDR; do
                    addr="${!addr_var}"
                    if [ -n "$addr" ] && [ "$addr" != "null" ]; then
                        addr_lower=$(echo "$addr" | tr '[:upper:]' '[:lower:]')

                        # Check if already in alloc
                        if ! jq -e ".\"$addr_lower\"" "$SNAPSHOT_DIR/el/alloc.json" >/dev/null 2>&1; then
                            echo "  Injecting $addr_var: $addr"

                            # Get code
                            CODE=$(cast code --rpc-url "$GETH_PORT" "$addr" 2>/dev/null || echo "0x")
                            # Get balance
                            BALANCE=$(cast balance --rpc-url "$GETH_PORT" "$addr" 2>/dev/null || echo "0")
                            # Get nonce
                            NONCE=$(cast nonce --rpc-url "$GETH_PORT" "$addr" 2>/dev/null || echo "0")

                            # Add to alloc with storage
                            if [ "$CODE" != "0x" ] && [ -n "$CODE" ]; then
                                echo -n "    Scanning storage slots..."

                                # Build storage object by scanning slots 0-99 and EIP-1967 proxy slots
                                STORAGE_JSON="{}"

                                # Scan regular slots 0-99
                                for slot_num in $(seq 0 99); do
                                    slot=$(printf "0x%x" $slot_num)
                                    value=$(cast storage --rpc-url "$GETH_PORT" "$addr" "$slot" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")

                                    if [ "$value" != "0x0000000000000000000000000000000000000000000000000000000000000000" ] && [ "$value" != "0x" ]; then
                                        # Pad slot to 32 bytes for alloc format
                                        slot_padded=$(printf "0x%064x" $slot_num)
                                        STORAGE_JSON=$(echo "$STORAGE_JSON" | jq --arg slot "$slot_padded" --arg val "$value" '.[$slot] = $val')
                                    fi
                                done

                                # Add EIP-1967 proxy slots
                                IMPL_SLOT="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
                                ADMIN_SLOT="0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"

                                for proxy_slot in "$IMPL_SLOT" "$ADMIN_SLOT"; do
                                    value=$(cast storage --rpc-url "$GETH_PORT" "$addr" "$proxy_slot" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
                                    if [ "$value" != "0x0000000000000000000000000000000000000000000000000000000000000000" ] && [ "$value" != "0x" ]; then
                                        STORAGE_JSON=$(echo "$STORAGE_JSON" | jq --arg slot "$proxy_slot" --arg val "$value" '.[$slot] = $val')
                                    fi
                                done

                                STORAGE_SLOTS=$(echo "$STORAGE_JSON" | jq 'keys | length')
                                echo " found $STORAGE_SLOTS non-zero slots"

                                # Add to alloc with storage
                                jq --arg addr "$addr_lower" \
                                   --arg code "$CODE" \
                                   --arg balance "$BALANCE" \
                                   --argjson nonce "$NONCE" \
                                   --argjson storage "$STORAGE_JSON" \
                                   '.[$addr] = {code: $code, balance: $balance, nonce: $nonce, storage: $storage}' \
                                   "$SNAPSHOT_DIR/el/alloc.json" > "$SNAPSHOT_DIR/el/alloc.json.tmp"
                                mv "$SNAPSHOT_DIR/el/alloc.json.tmp" "$SNAPSHOT_DIR/el/alloc.json"

                                echo "    ✅ Injected with code (${#CODE} bytes) and $STORAGE_SLOTS storage slots"
                            else
                                echo "    ⚠️  No code found, skipping"
                            fi
                        fi
                    fi
                done

                rm -f "$TMP_CONTRACTS"
                break
            fi
        fi
    done
else
    echo "  No contracts service found - skipping contract injection"
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

# Extract OP stack configuration if present
echo "Checking for OP stack services..."
if kurtosis files inspect "$ENCLAVE_NAME" op-deployer-configs &>/dev/null; then
    echo "✅ OP stack detected - extracting configuration"
    mkdir -p "$SNAPSHOT_DIR/op"

    # Download OP deployer configs
    TMP_OP_CONFIGS="/tmp/kurtosis-op-configs-$$"
    kurtosis files download "$ENCLAVE_NAME" op-deployer-configs "$TMP_OP_CONFIGS" >/dev/null 2>&1

    # Find L2 chain ID from rollup config
    L2_CHAIN_ID=$(ls "$TMP_OP_CONFIGS"/rollup-*.json 2>/dev/null | head -1 | sed 's/.*rollup-\([0-9]*\)\.json/\1/')

    if [ -n "$L2_CHAIN_ID" ]; then
        echo "  L2 Chain ID: $L2_CHAIN_ID"

        # Copy essential config files
        cp "$TMP_OP_CONFIGS/genesis-${L2_CHAIN_ID}.json" "$SNAPSHOT_DIR/op/" 2>/dev/null || echo "Warning: genesis not found"
        cp "$TMP_OP_CONFIGS/rollup-${L2_CHAIN_ID}.json" "$SNAPSHOT_DIR/op/rollup-${L2_CHAIN_ID}.json.template" 2>/dev/null || echo "Warning: rollup config not found"
        cp "$TMP_OP_CONFIGS/state.json" "$SNAPSHOT_DIR/op/" 2>/dev/null || echo "Warning: state.json not found"
        cp "$TMP_OP_CONFIGS/wallets.json" "$SNAPSHOT_DIR/op/" 2>/dev/null || echo "Warning: wallets.json not found"
        echo "  Note: rollup config will be patched with fresh L1 genesis on startup"

        # Copy L1 genesis for op-node --rollup.l1-chain-config flag
        TMP_L1_GENESIS="/tmp/kurtosis-l1-genesis-$$"
        kurtosis files download "$ENCLAVE_NAME" el_cl_genesis_data "$TMP_L1_GENESIS" >/dev/null 2>&1
        if [ -f "$TMP_L1_GENESIS/genesis.json" ]; then
            # Remove terminalTotalDifficultyPassed field which is not compatible with op-node
            cat "$TMP_L1_GENESIS/genesis.json" | jq 'del(.config.terminalTotalDifficultyPassed)' > "$SNAPSHOT_DIR/op/l1-genesis.json"
            echo "  ✅ L1 genesis copied (cleaned for op-node compatibility)"
        else
            echo "  Warning: L1 genesis not found"
        fi
        rm -rf "$TMP_L1_GENESIS"

        echo "✅ OP stack config files extracted"
    else
        echo "Warning: Could not determine L2 chain ID"
    fi

    rm -rf "$TMP_OP_CONFIGS"
else
    echo "  No OP stack services found - skipping"
fi
echo ""

# Extract aggkit configuration if present
echo "Checking for aggkit services..."
AGGKIT_SVC="aggkit-001"
if kurtosis service inspect "$ENCLAVE_NAME" "$AGGKIT_SVC" &>/dev/null; then
    echo "✅ Aggkit detected - extracting configuration"
    mkdir -p "$SNAPSHOT_DIR/aggkit"

    # Use aggkit:local for snapshots (has bug fixes for contract sanity checks)
    export AGGKIT_IMAGE="aggkit:local"
    echo "  Aggkit image: $AGGKIT_IMAGE"

    # Extract deployed contract addresses FIRST (needed for config patching)
    TMP_DEPLOYED_CONTRACTS="/tmp/kurtosis-deployed-$$"
    DEPLOYED_CONTRACTS_FOUND=false
    for contracts_file in "/opt/agglayer-contracts/deployment/v2/deploy_output.json" "/opt/combined.json" "/opt/deploy_output.json" "/opt/deployed_contracts.json"; do
        if timeout 5 kurtosis service exec "$ENCLAVE_NAME" contracts-001 "cat $contracts_file" > "$TMP_DEPLOYED_CONTRACTS" 2>/dev/null; then
            if [ -s "$TMP_DEPLOYED_CONTRACTS" ] && jq empty "$TMP_DEPLOYED_CONTRACTS" 2>/dev/null; then
                echo "  ✅ Found contract addresses in $contracts_file"
                DEPLOYED_CONTRACTS_FOUND=true
                break
            fi
        fi
    done

    # Download aggkit config artifact
    TMP_AGGKIT_CONFIG="/tmp/kurtosis-aggkit-config-$$"
    if kurtosis files download "$ENCLAVE_NAME" aggkit-config-001 "$TMP_AGGKIT_CONFIG" >/dev/null 2>&1; then
        # Copy original config
        cp "$TMP_AGGKIT_CONFIG/config.toml" "$SNAPSHOT_DIR/aggkit/config.toml.template" 2>/dev/null || echo "Warning: aggkit config not found"

        # Create docker-compose version with patched URLs, writable paths, AND actual contract addresses
        if [ -f "$SNAPSHOT_DIR/aggkit/config.toml.template" ]; then
            # Start with URL and path patches
            cat "$SNAPSHOT_DIR/aggkit/config.toml.template" | \
              sed 's|L1URL = ".*"|L1URL = "http://geth:8545"|g' | \
              sed 's|L2URL = ".*"|L2URL = "http://op-geth:8545"|g' | \
              sed 's|OpNodeURL = ".*"|OpNodeURL = "http://op-node:8547"|g' | \
              sed 's|AggLayerURL = ".*"|AggLayerURL = "http://agglayer:9600"|g' | \
              sed 's|RPCURL = ".*"|RPCURL = "http://geth:8545"|g' | \
              sed 's|URLRPCL2 = ".*"|URLRPCL2 = "http://op-geth:8545"|g' | \
              sed 's|URLRPCL1 = ".*"|URLRPCL1 = "http://geth:8545"|g' | \
              sed 's|PathRWData = ".*"|PathRWData = "/tmp"|g' | \
              sed 's|^\([[:space:]]*\)URL = "http://el-[^"]*"|\1URL = "http://geth:8545"|g' | \
              sed 's|^\([[:space:]]*\)URL = "http://agglayer:[^"]*"|\1URL = "http://agglayer:9600"|g' | \
              sed 's|^rollupCreationBlockNumber = ".*"|rollupCreationBlockNumber = "1"|g' | \
              sed 's|^rollupManagerCreationBlockNumber = ".*"|rollupManagerCreationBlockNumber = "1"|g' | \
              sed 's|^genesisBlockNumber = ".*"|genesisBlockNumber = "1"|g' | \
              sed 's|^InitialBlock = ".*"|InitialBlock = "1"|g' | \
              sed 's|^RollupCreationBlockL1 = ".*"|RollupCreationBlockL1 = "1"|g' \
              > "$SNAPSHOT_DIR/aggkit/config.toml"

            # Patch contract addresses if we found them
            if [ "$DEPLOYED_CONTRACTS_FOUND" = true ]; then
                echo "  Patching aggkit config with actual deployed contract addresses..."

                # Extract actual addresses from deployed contracts
                GER_ADDR=$(jq -r '.polygonZkEVMGlobalExitRootAddress // .AgglayerGER // empty' "$TMP_DEPLOYED_CONTRACTS" 2>/dev/null)
                ROLLUP_MANAGER_ADDR=$(jq -r '.polygonRollupManagerAddress // .AgglayerManager // empty' "$TMP_DEPLOYED_CONTRACTS" 2>/dev/null)
                BRIDGE_ADDR=$(jq -r '.polygonZkEVMBridgeAddress // .AgglayerBridge // empty' "$TMP_DEPLOYED_CONTRACTS" 2>/dev/null)
                ROLLUP_ADDR=$(jq -r '.rollupAddress // .polygonZkEVMAddress // empty' "$TMP_DEPLOYED_CONTRACTS" 2>/dev/null)

                # Patch config with actual addresses
                if [ -n "$GER_ADDR" ]; then
                    echo "    GlobalExitRoot: $GER_ADDR"
                    sed -i "s|polygonZkEVMGlobalExitRootAddress = \".*\"|polygonZkEVMGlobalExitRootAddress = \"$GER_ADDR\"|g" "$SNAPSHOT_DIR/aggkit/config.toml"
                fi
                if [ -n "$ROLLUP_MANAGER_ADDR" ]; then
                    echo "    RollupManager: $ROLLUP_MANAGER_ADDR"
                    sed -i "s|polygonRollupManagerAddress = \".*\"|polygonRollupManagerAddress = \"$ROLLUP_MANAGER_ADDR\"|g" "$SNAPSHOT_DIR/aggkit/config.toml"
                fi
                if [ -n "$BRIDGE_ADDR" ]; then
                    echo "    Bridge: $BRIDGE_ADDR"
                    sed -i "s|polygonZkEVMBridgeAddress = \".*\"|polygonZkEVMBridgeAddress = \"$BRIDGE_ADDR\"|g" "$SNAPSHOT_DIR/aggkit/config.toml"
                fi
                if [ -n "$ROLLUP_ADDR" ]; then
                    echo "    Rollup: $ROLLUP_ADDR"
                    sed -i "s|rollupAddress = \".*\"|rollupAddress = \"$ROLLUP_ADDR\"|g" "$SNAPSHOT_DIR/aggkit/config.toml"
                fi
            else
                echo "  ⚠️  WARNING: Using template contract addresses (actual addresses not found)"
                echo "  This may cause aggkit to fail!"
            fi
        fi
        echo "  ✅ Aggkit config extracted and patched for docker-compose"
    fi
    rm -rf "$TMP_AGGKIT_CONFIG"

    # Download aggkit keystores from contracts service
    # Extract keystores from contracts service directly to aggkit directory
    for keystore in sequencer aggoracle sovereignadmin aggregator; do
        kurtosis service exec "$ENCLAVE_NAME" contracts-001 "cat /opt/keystores/${keystore}.keystore" > "$SNAPSHOT_DIR/aggkit/${keystore}.keystore" 2>/dev/null
        if [ -s "$SNAPSHOT_DIR/aggkit/${keystore}.keystore" ]; then
            echo "  ✅ Extracted ${keystore}.keystore"
        else
            echo "  Warning: Could not extract ${keystore}.keystore"
            rm -f "$SNAPSHOT_DIR/aggkit/${keystore}.keystore"
        fi
    done

    # Extract wallets.json for addresses (with timeout)
    timeout 5 kurtosis service exec "$ENCLAVE_NAME" contracts-001 "cat /opt/wallets.json" > "$SNAPSHOT_DIR/aggkit/wallets.json" 2>/dev/null || true
    if [ -s "$SNAPSHOT_DIR/aggkit/wallets.json" ]; then
        echo "  ✅ Extracted wallets.json"
    else
        echo "  Warning: Could not extract wallets.json (skipping)"
        echo "{}" > "$SNAPSHOT_DIR/aggkit/wallets.json"
    fi

    # Save deployed contracts for reference
    if [ "$DEPLOYED_CONTRACTS_FOUND" = true ]; then
        cp "$TMP_DEPLOYED_CONTRACTS" "$SNAPSHOT_DIR/aggkit/deployed_contracts.json"
        echo "  ✅ Saved deployed contract addresses to deployed_contracts.json"
    else
        echo "  ⚠️  WARNING: Could not extract deployed contract addresses"
        echo "  Tried: /opt/combined.json, /opt/deploy_output.json, /opt/deployed_contracts.json"
        echo "{}" > "$SNAPSHOT_DIR/aggkit/deployed_contracts.json"
    fi
    rm -f "$TMP_DEPLOYED_CONTRACTS"

    echo "✅ Aggkit configuration extracted"
else
    echo "  No aggkit services found - skipping"
fi
echo ""

# Extract agglayer configuration if present
echo "Checking for agglayer services..."
AGGLAYER_SVC="agglayer"
if kurtosis service inspect "$ENCLAVE_NAME" "$AGGLAYER_SVC" &>/dev/null; then
    echo "✅ Agglayer detected - extracting configuration"
    mkdir -p "$SNAPSHOT_DIR/agglayer"

    # Download agglayer config artifact
    TMP_AGGLAYER_CONFIG="/tmp/kurtosis-agglayer-config-$$"
    if kurtosis files download "$ENCLAVE_NAME" agglayer-config "$TMP_AGGLAYER_CONFIG" >/dev/null 2>&1; then
        # Copy original config
        cp "$TMP_AGGLAYER_CONFIG/config.toml" "$SNAPSHOT_DIR/agglayer/config.toml.template" 2>/dev/null || echo "Warning: agglayer config not found"
        # Create docker-compose version with patched URLs and writable paths
        if [ -f "$SNAPSHOT_DIR/agglayer/config.toml.template" ]; then
            cat "$SNAPSHOT_DIR/agglayer/config.toml.template" | \
              sed 's|node-url = ".*"|node-url = "http://geth:8545"|g' | \
              sed 's|ws-node-url = ".*"|ws-node-url = "ws://geth:8546"|g' | \
              sed 's|db-path = ".*"|db-path = "/tmp/agglayer/storage"|g' | \
              sed '/\[storage\.backup\]/,/^$/ s|path = ".*"|path = "/tmp/agglayer/backups"|' | \
              sed 's|{ path = "/etc/agglayer/aggregator.keystore"|{ path = "/config/aggregator.keystore"|g' \
              > "$SNAPSHOT_DIR/agglayer/config.toml"
        fi
        # Copy aggregator keystore to agglayer directory
        if [ -f "$SNAPSHOT_DIR/aggkit/aggregator.keystore" ]; then
            cp "$SNAPSHOT_DIR/aggkit/aggregator.keystore" "$SNAPSHOT_DIR/agglayer/"
        fi
        echo "  ✅ Agglayer config extracted and patched for docker-compose"
    fi
    rm -rf "$TMP_AGGLAYER_CONFIG"

    echo "✅ Agglayer configuration extracted"
else
    echo "  No agglayer services found - skipping"
fi
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
