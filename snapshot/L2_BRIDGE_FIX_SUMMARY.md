# L2 Bridge Smart Contract Extraction - Fix Summary

## Problem Statement

L2 networks (especially OP-Geth networks) require bridge smart contracts to be present in the genesis and properly configured in the aggkit config. The snapshot creation tooling was not properly extracting and injecting the L2 Bridge and GlobalExitRoot (GER) contract addresses.

### Observed Issues

1. **AggKit Config Missing Bridge Addresses**: The aggkit-config.toml had commented-out `BridgeAddr` fields:
   ```toml
   [L2Config]
   GlobalExitRootAddr = "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa"
   # BridgeAddr removed - L2 bridge not available in snapshot
   ```

2. **BridgeL2Sync Section Removed**: The entire `[BridgeL2Sync]` section was commented out in the config.

3. **summary.json Missing L2 Contracts**: The network summary didn't include L2 bridge contract addresses.

## Root Cause

The L2 contract extraction script (`extract-l2-contracts.sh`) was:
1. Not logging enough information to diagnose extraction failures
2. Not handling both CDK and standard Geth genesis formats when validating addresses
3. Too strict in validation - clearing addresses if not found in genesis (even though they might be valid)

The config injection script (`process-configs.sh`) was:
1. Not verifying that addresses were actually injected
2. Not providing clear error messages when injection failed
3. Completely removing the BridgeL2Sync section instead of leaving placeholders

## Changes Made

### 1. Enhanced L2 Contract Extraction (`extract-l2-contracts.sh`)

**Improved Logging**:
- Added debug output when reading `create-sovereign-genesis-output.json`
- Log extracted addresses immediately after reading
- Provide clear warnings about what might be wrong if extraction fails

**Multi-Format Genesis Support**:
- Now checks both CDK format (`.genesis[]` array) and standard Geth format (`.alloc{}` object)
- Doesn't clear addresses if not found in genesis (they might be valid pre-deployed addresses)
- Added fallback path checking (`/opt/output/` and `/opt/zkevm/`)

**Better Error Messages**:
```bash
if [ -z "${l2_ger_addr}" ] || [ -z "${l2_bridge_addr}" ]; then
    log_warn "L2 contract addresses not found in create-sovereign-genesis-output.json"
    log_info "This might indicate:"
    log_info "  1. The contracts service hasn't created the output file yet"
    log_info "  2. This is an OP-Geth network using a different genesis format"
    log_info "  3. The sovereign genesis creation step didn't complete"
fi
```

### 2. Robust Config Injection (`process-configs.sh`)

**Enhanced AWK Script**:
- Tracks whether BridgeAddr was added to L2Config
- Handles commented-out lines properly
- Ensures addresses are injected even if fields were previously removed

**Verification After Injection**:
```bash
if grep -q "BridgeAddr.*${l2_bridge_addr}" "${output_file}" &&
   grep -q "GlobalExitRootAddr.*${l2_ger_addr}" "${output_file}"; then
    echo "✅ Verified L2 contract addresses in aggkit config"
else
    echo "⚠️  Warning: L2 contract addresses may not have been properly injected"
fi
```

**Graceful Fallback**:
- If extraction fails, leaves placeholder comments instead of removing sections entirely
- Provides clear TODO comments for manual configuration:
  ```toml
  # BridgeAddr = "" # TODO: Update with actual L2 bridge address
  ```

### 3. Preserved BridgeL2Sync Section

Instead of removing the `[BridgeL2Sync]` section when contracts aren't found:
```toml
# OLD BEHAVIOR (removed section):
# [BridgeL2Sync] section removed - L2 bridge not available in snapshot

# NEW BEHAVIOR (preserved with placeholder):
# [BridgeL2Sync] WARNING: L2 bridge address not extracted - update this manually
[BridgeL2Sync]
# BridgeAddr = "" # TODO: Update with actual L2 bridge address
```

## Testing the Fix

### Prerequisites
- Kurtosis installed and running
- Docker and Docker Compose installed
- `jq` installed for JSON processing

### Test Procedure

1. **Create a Snapshot**:
   ```bash
   ./snapshot/scripts/snapshot.sh \
       --enclave-name snapshot \
       --output-dir ./snapshot-output \
       --networks ./snapshot/test-config.json \
       --cleanup-enclave
   ```

2. **Validate L2 Contract Extraction**:
   ```bash
   # Check if l2-contracts.json exists for each network
   for network_dir in ./snapshot-output/configs/*/; do
       if [ -d "$network_dir" ]; then
           network_id=$(basename "$network_dir")
           echo "Checking network ${network_id}..."

           if [ -f "${network_dir}/l2-contracts.json" ]; then
               echo "  ✅ l2-contracts.json exists"
               l2_ger=$(jq -r '.l2_ger_address' "${network_dir}/l2-contracts.json")
               l2_bridge=$(jq -r '.l2_bridge_address' "${network_dir}/l2-contracts.json")
               echo "     L2 GER: ${l2_ger}"
               echo "     L2 Bridge: ${l2_bridge}"
           else
               echo "  ❌ l2-contracts.json NOT found"
           fi
       fi
   done
   ```

3. **Validate AggKit Config**:
   ```bash
   # Check if aggkit-config.toml has the addresses
   for network_dir in ./snapshot-output/configs/*/; do
       if [ -d "$network_dir" ]; then
           network_id=$(basename "$network_dir")
           config_file="${network_dir}/aggkit-config.toml"

           if [ -f "$config_file" ]; then
               echo "Checking aggkit config for network ${network_id}..."

               # Check L2Config.BridgeAddr
               if grep -q "^BridgeAddr = \"0x" "$config_file"; then
                   bridge_addr=$(grep "^BridgeAddr" "$config_file" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1)
                   echo "  ✅ L2Config.BridgeAddr: ${bridge_addr}"
               else
                   echo "  ❌ L2Config.BridgeAddr not set"
               fi

               # Check L2Config.GlobalExitRootAddr
               if grep -q "^GlobalExitRootAddr = \"0x" "$config_file"; then
                   ger_addr=$(grep "^GlobalExitRootAddr" "$config_file" | sed 's/.*= *"\([^"]*\)".*/\1/' | head -1)
                   echo "  ✅ L2Config.GlobalExitRootAddr: ${ger_addr}"
               else
                   echo "  ❌ L2Config.GlobalExitRootAddr not set"
               fi

               # Check if BridgeL2Sync section exists
               if grep -q "^\[BridgeL2Sync\]" "$config_file"; then
                   echo "  ✅ [BridgeL2Sync] section exists"
               else
                   echo "  ❌ [BridgeL2Sync] section not found"
               fi
           fi
       fi
   done
   ```

4. **Validate Summary**:
   ```bash
   # Check if summary.json includes L2 contracts
   if [ -f "./snapshot-output/summary.json" ]; then
       echo "Checking summary.json..."

       network_count=$(jq '.l2_networks | length' ./snapshot-output/summary.json)
       echo "Found ${network_count} L2 network(s) in summary"

       for i in $(seq 0 $((network_count - 1))); do
           network_id=$(jq -r ".l2_networks[$i].network_id" ./snapshot-output/summary.json)
           l2_ger=$(jq -r ".l2_networks[$i].contracts.l2_global_exit_root // \"\"" ./snapshot-output/summary.json)
           l2_bridge=$(jq -r ".l2_networks[$i].contracts.l2_bridge // \"\"" ./snapshot-output/summary.json)

           echo "Network ${network_id}:"
           if [ -n "$l2_ger" ] && [ "$l2_ger" != "null" ]; then
               echo "  ✅ L2 GER: ${l2_ger}"
           else
               echo "  ❌ L2 GER not in summary"
           fi

           if [ -n "$l2_bridge" ] && [ "$l2_bridge" != "null" ]; then
               echo "  ✅ L2 Bridge: ${l2_bridge}"
           else
               echo "  ❌ L2 Bridge not in summary"
           fi
       done
   fi
   ```

5. **Test Runtime**:
   ```bash
   cd ./snapshot-output
   docker-compose up -d

   # Wait for services to start
   sleep 30

   # Check if aggkit can connect to L2 bridge
   docker-compose logs aggkit-1 | grep -i bridge

   # Verify bridge contract exists on L2
   cast call 0x<L2_BRIDGE_ADDRESS> "getTokenWrappedAddress(uint32,address)" 1 0x0000000000000000000000000000000000000000 \
       --rpc-url http://localhost:8545
   ```

## Expected Results

After the fix:

1. **L2 Contracts Extracted**: Each network should have a `configs/<network_id>/l2-contracts.json` file with:
   ```json
   {
     "l2_ger_address": "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa",
     "l2_bridge_address": "0x2a3dd3eb832af982ec71669e178424b10dca2ede",
     "extracted_at": "2025-01-30T...",
     "source": "genesis_artifact"
   }
   ```

2. **AggKit Config Updated**: The `aggkit-config.toml` should have:
   ```toml
   [L2Config]
   GlobalExitRootAddr = "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa"
   BridgeAddr = "0x2a3dd3eb832af982ec71669e178424b10dca2ede"
   ```

3. **BridgeL2Sync Enabled**: The `[BridgeL2Sync]` section should exist:
   ```toml
   [BridgeL2Sync]
   BridgeAddr = "0x2a3dd3eb832af982ec71669e178424b10dca2ede"
   ```

4. **Summary Includes Contracts**: The `summary.json` should show:
   ```json
   {
     "l2_networks": [
       {
         "network_id": 1,
         "contracts": {
           "l2_global_exit_root": "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa",
           "l2_bridge": "0x2a3dd3eb832af982ec71669e178424b10dca2ede"
         }
       }
     ]
   }
   ```

## Troubleshooting

### If L2 Contracts Are Still Not Extracted

1. **Check Contracts Service Exists**:
   ```bash
   kurtosis enclave inspect snapshot | grep contracts
   ```

2. **Verify create-sovereign-genesis-output.json Exists**:
   ```bash
   kurtosis service exec snapshot contracts-001 \
       "sh -c 'ls -la /opt/output/create-sovereign-genesis-output.json'"
   ```

3. **Manually Extract File**:
   ```bash
   kurtosis service exec snapshot contracts-001 \
       "sh -c 'cat /opt/output/create-sovereign-genesis-output.json'" | jq .
   ```

4. **Check Genesis Artifact**:
   ```bash
   kurtosis files download snapshot genesis-001 /tmp/genesis-check
   cat /tmp/genesis-check/genesis.json | jq '.alloc | keys | length'
   ```

### If Injection Fails

Check the process-configs.sh log output:
```bash
grep -A 5 "Injecting L2 contract addresses" ./snapshot-output/config-processing.log
```

### If Bridge Doesn't Work at Runtime

1. Verify the contract exists at the address:
   ```bash
   cast code 0x<BRIDGE_ADDRESS> --rpc-url http://localhost:8545
   ```

2. Check if the address is in the genesis:
   ```bash
   cat ./snapshot-output/configs/1/genesis.json | jq '.alloc."0x<bridge_address>"'
   ```

## Additional Notes

- For OP-Geth networks, the L2 bridge contracts are deployed as part of the sovereign genesis creation
- The contract addresses are stored in `create-sovereign-genesis-output.json` by the contracts deployment script
- The addresses should match the addresses in the L2 genesis (`.alloc{}` object)
- Both `AgglayerBridgeL2 proxy` and `AgglayerGERL2 proxy` are required for bridge functionality

## References

- [Snapshot Documentation](./README.md)
- [AggKit Configuration](https://github.com/agglayer/aggkit)
- [Contract Deployment Script](../static_files/contracts/contracts.sh)
