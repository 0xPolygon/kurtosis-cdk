# Agglayer Gas Price Configuration Fix

## Problem

Agglayer settlement transactions were failing to be mined on L1 due to extremely low gas fees:
- L1 requires minimum priority fee: **1,000,000 wei** (1 gwei)
- Agglayer was submitting with: **12-120 wei**
- Result: Transactions stuck in pending pool, never mined

## Root Cause

1. **L1 Configuration**: Geth's default `--miner.gasprice` is 1,000,000 wei
2. **Agglayer Behavior**:
   - Uses `eth_feeHistory` to estimate fees
   - Returns base fee = 7 wei, priority reward = 0 wei (empty blocks)
   - Applies multiplier (1.75x): 7 * 1.75 = ~12 wei
   - Even with retries (1.5x each), never reaches required 1,000,000+ wei
3. **Result**: After 6 failed settlement attempts, certificate enters "InError" state

## Solution

Updated `snapshot/scripts/adapt-agglayer-config.sh` to add gas price floor configuration:

```toml
[outbound.rpc.settle.gas-price]
floor = "1gwei"        # 1 gwei minimum (L1 default miner.gasprice is 0.001 gwei)
ceiling = "100gwei"    # 100 gwei maximum
multiplier = 1000      # 1.0x multiplier (scaled by 1000)
```

## Implementation Details

### Script Location
`snapshot/scripts/adapt-agglayer-config.sh`

### Changes Made
1. Added gas price configuration section after `gas-multiplier-factor` in `[outbound.rpc.settle]`
2. Uses string format with units (required by `EthAmount` deserializer):
   - `floor = "1gwei"` (not `floor = 1000000000`)
   - `ceiling = "100gwei"` (not `ceiling = 100000000000`)
3. Updated header comment to document the change
4. Added summary output showing configured gas price floor

### Configuration Format Notes

The agglayer config uses `#[serde_as(as = "crate::with::EthAmount")]` for gas price values, which means:
- Values MUST be strings with units: `"1gwei"`, `"0.1eth"`, `"1000000000wei"`
- Integer values will cause deserialization errors
- Supported units: `wei`, `gwei`, `eth`

### Config Structure

The configuration supports both:
- **Legacy**: `[outbound.rpc.settle]` with `gas-multiplier-factor`
- **Modern**: `[outbound.rpc.settle.gas-price]` with floor/ceiling/multiplier

Both can coexist. The gas-price config takes precedence for fee calculation.

## Testing

Tested on existing snapshot `cdk-20260204-122111`:
1. Applied updated `adapt-agglayer-config.sh` script
2. Verified configuration format is correct
3. Restarted agglayer container
4. Confirmed agglayer starts successfully and is healthy
5. Agglayer now processing L1 blocks normally

## Future Snapshots

All future snapshots created with the updated script will:
1. Automatically have gas price floor configured during snapshot creation
2. Submit settlement transactions with sufficient gas fees (≥1 gwei)
3. Successfully settle certificates on L1 without transaction failures

## Files Modified

- `snapshot/scripts/adapt-agglayer-config.sh`

## Related Agglayer Code

Key files in `~/agglayer`:
- `crates/agglayer-config/src/outbound.rs` - Config structures
- `crates/agglayer-contracts/src/lib.rs` - `adjust_gas_estimate()` function
- `crates/agglayer-contracts/src/settler.rs` - Settlement transaction builder
- `crates/agglayer-config/src/multiplier.rs` - Multiplier type (scaled by 1000)

## Verification

To verify the fix works in a new snapshot:
1. Create a new snapshot: `./snapshot/snapshot.sh <enclave-name>`
2. Check agglayer config has gas price floor:
   ```bash
   grep -A5 "gas-price" snapshots/<snapshot-name>/config/agglayer/config.toml
   ```
3. Start the snapshot and verify settlement transactions have proper gas fees:
   ```bash
   docker logs <snapshot-name>-agglayer 2>&1 | grep -i "gas\|fee"
   ```
4. Check L1 txpool for settlement transactions with maxFeePerGas ≥ 1 gwei:
   ```bash
   docker exec <snapshot-name>-geth geth attach --exec 'txpool.content.pending' http://localhost:8545
   ```

## Alternative Solutions Considered

1. **Lower L1 minimum gas price**: Could configure geth with lower `--miner.gasprice`
   - Rejected: Would require modifying L1 genesis/config, more invasive

2. **Increase agglayer multiplier**: Use higher `gas-multiplier-factor`
   - Rejected: Still wouldn't work when base fee is very low (7 wei * even 10x = 70 wei)

3. **Add gas price floor** (chosen solution):
   - Most robust: Works regardless of L1 base fee estimation
   - Simple: Only requires agglayer config change
   - Safe: Ceiling prevents overpaying on high-fee networks

## Credits

Issue diagnosed by analyzing:
- Agglayer logs showing settlement failures
- L1 transaction pool status
- Geth default configuration
- Agglayer gas price calculation code
