# Snapshot Creation Fix - L2 Bridge Smart Contracts

## Summary

Fixed critical issues in the snapshot creation tooling where L2 Bridge and Global Exit Root (GER) smart contract addresses were not being properly extracted from the Kurtosis enclave and injected into the configuration files.

## Changes Made

### 1. Enhanced L2 Contract Extraction Script
**File**: `snapshot/scripts/extract-l2-contracts.sh`

**Improvements**:
- Added detailed logging to debug extraction process
- Added support for multiple file paths (`/opt/output/` and `/opt/zkevm/`)
- Added validation for both CDK genesis format (`.genesis[]`) and standard Geth format (`.alloc{}`)
- No longer clears addresses if not found in genesis (they may be valid pre-deployed addresses)
- Better error messages explaining potential issues

### 2. Improved Config Injection Logic
**File**: `snapshot/scripts/process-configs.sh`

**Improvements**:
- Enhanced AWK script to properly track and inject addresses
- Added verification after injection to confirm addresses were written
- Preserved `[BridgeL2Sync]` section with placeholders instead of removing it
- Added clear TODO comments for manual configuration if extraction fails
- Better handling of commented-out fields

### 3. Created Validation Script
**File**: `snapshot/scripts/validate-l2-contracts.sh`

A new automated validation script that checks:
- L2 contract addresses are extracted to `l2-contracts.json`
- Addresses are properly injected into `aggkit-config.toml`
- Addresses are included in `summary.json`
- Genesis contains the contract addresses (both formats)

### 4. Comprehensive Documentation
**File**: `snapshot/L2_BRIDGE_FIX_SUMMARY.md`

Detailed documentation including:
- Problem statement and root cause analysis
- Complete list of changes made
- Testing procedures with example commands
- Troubleshooting guide
- Expected results

## How to Use

### Step 1: Create a Snapshot

Use the snapshot creation script as referenced in the main README:

```bash
./snapshot/scripts/snapshot.sh \
    --enclave-name snapshot \
    --output-dir ./snapshot-output \
    --networks ./snapshot/test-config.json \
    --cleanup-enclave
```

### Step 2: Validate the Snapshot

Run the validation script to ensure L2 contracts were properly extracted:

```bash
./snapshot/scripts/validate-l2-contracts.sh --output-dir ./snapshot-output
```

**Expected Output**:
```
========================================
Validation Summary
========================================

Total networks found: 1
Networks with valid l2-contracts.json: 1/1
Networks with valid aggkit config: 1/1
Networks in summary with L2 contracts: 1/1

✅ All validations passed!
```

### Step 3: Review the Configuration

Check the generated configuration files:

1. **L2 Contract Addresses** (`snapshot-output/configs/1/l2-contracts.json`):
```json
{
  "l2_ger_address": "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa",
  "l2_bridge_address": "0x2a3dd3eb832af982ec71669e178424b10dca2ede",
  "extracted_at": "2025-01-30T...",
  "source": "genesis_artifact"
}
```

2. **AggKit Configuration** (`snapshot-output/configs/1/aggkit-config.toml`):
```toml
[L2Config]
GlobalExitRootAddr = "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa"
BridgeAddr = "0x2a3dd3eb832af982ec71669e178424b10dca2ede"
L2URL = "http://op-geth-1:8545"
# ... other config ...

[BridgeL2Sync]
BridgeAddr = "0x2a3dd3eb832af982ec71669e178424b10dca2ede"
# ... other config ...
```

3. **Network Summary** (`snapshot-output/summary.json`):
```json
{
  "l2_networks": [
    {
      "network_id": 1,
      "contracts": {
        "l2_global_exit_root": "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa",
        "l2_bridge": "0x2a3dd3eb832af982ec71669e178424b10dca2ede",
        "l1_rollup_contract": "0x..."
      },
      "accounts": [...],
      "rpc": {...}
    }
  ]
}
```

### Step 4: Test the Snapshot

Start the snapshot environment:

```bash
cd snapshot-output
docker-compose up -d
```

Verify the bridge contract is accessible:

```bash
# Get the L2 bridge address from summary
L2_BRIDGE=$(jq -r '.l2_networks[0].contracts.l2_bridge' summary.json)

# Check the contract exists on L2
cast code "$L2_BRIDGE" --rpc-url http://localhost:8545
```

If the contract exists, you should see a long hex string (the bytecode).

## Troubleshooting

### If Validation Fails

1. **Check the extraction logs**:
```bash
grep -A 10 "Extracting L2 contract addresses" snapshot-output/*.log
```

2. **Verify the contracts service exists in Kurtosis**:
```bash
kurtosis enclave inspect snapshot | grep contracts
```

3. **Check if create-sovereign-genesis-output.json exists**:
```bash
kurtosis service exec snapshot contracts-001 \
    "sh -c 'cat /opt/output/create-sovereign-genesis-output.json'" | jq .
```

4. **Review detailed troubleshooting guide**:
```bash
cat snapshot/L2_BRIDGE_FIX_SUMMARY.md
```

### Common Issues

1. **"L2 contracts file not found"**: The extraction script may have failed. Check if the contracts service completed successfully.

2. **"BridgeAddr commented out"**: The injection may have failed. Check process-configs.sh logs for errors.

3. **"Addresses don't match genesis"**: This is a warning, not an error. The contracts may be deployed at runtime.

## Technical Details

### Where L2 Contracts Come From

For OP-Geth (sovereign) networks:
1. The contracts deployment service runs `create_sovereign_genesis` function
2. This creates `create-sovereign-genesis-output.json` with contract mappings
3. The contracts are included in the L2 genesis file
4. The extraction script reads the mappings and saves to `l2-contracts.json`

### Why L2 Bridge Contracts Are Required

L2 Bridge contracts are essential for:
- **Cross-chain transfers**: Moving assets between L1 and L2
- **Message passing**: Sending messages between chains
- **Agglayer connectivity**: Connecting L2 to the AggLayer
- **Exit root synchronization**: Syncing state roots between chains

Without these contracts properly configured, the AggKit aggregator will fail to:
- Sync bridge events from L2
- Generate proofs for cross-chain transactions
- Submit batches to the AggLayer

## Files Modified

1. `snapshot/scripts/extract-l2-contracts.sh` - Enhanced extraction logic
2. `snapshot/scripts/process-configs.sh` - Improved config injection
3. `snapshot/scripts/validate-l2-contracts.sh` - New validation script
4. `snapshot/L2_BRIDGE_FIX_SUMMARY.md` - Detailed documentation

## Next Steps

1. **Create a snapshot** using the command from the main README
2. **Validate the snapshot** using the validation script
3. **Test the snapshot** by starting docker-compose and verifying bridge functionality
4. **Report any issues** with detailed logs from the validation script

## References

- [Snapshot README](snapshot/README.md)
- [L2 Bridge Fix Summary](snapshot/L2_BRIDGE_FIX_SUMMARY.md)
- [Main README](README.md) - See "Snapshot Feature" section
