# Aggoracle Funding Fix

## Problem
The aggoracle didn't have funds on L2 in snapshot-generated environments, causing the following error:
```
insufficient funds for gas * price + value: balance 0, tx cost 23042065457660
```

## Root Cause
When snapshots are created, the L2 state is not preserved (it's stateless by design). The L2 starts from genesis when the snapshot is restored. During the initial Kurtosis deployment, the aggoracle address is funded via `cast send` transactions, but these funds are lost when the snapshot restarts from genesis.

## Solution
Modified `/home/aigent/kurtosis-cdk/snapshot/scripts/adapt-l2-config.sh` to add account allocations to the L2 genesis file during snapshot creation. This ensures the following accounts have funds from genesis:

- **aggoracle** (0x0b68058E5b2592b1f472AdFe106305295A332A7C): 100 ETH
- **sovereignadmin** (0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16): 100 ETH  
- **claimsponsor** (0x635243A11B41072264Df6c9186e3f473402F94e9): 100 ETH

## Changes Made
1. Modified `snapshot/scripts/adapt-l2-config.sh` to inject account allocations into the L2 genesis JSON
2. Created new snapshot: `cdk-20260203-083342`

## Verification Results
✅ New snapshot created successfully
✅ All accounts funded from genesis (100 ETH each)
✅ Aggkit running for 5+ minutes with ZERO "insufficient funds" errors
✅ L2 producing blocks normally (block 406+ verified)
✅ Aggoracle sending transactions successfully

## Files Modified
- `/home/aigent/kurtosis-cdk/snapshot/scripts/adapt-l2-config.sh`

## New Snapshot Location
`/home/aigent/kurtosis-cdk/snapshots/cdk-20260203-083342/`

## Usage
To use the new snapshot:
```bash
cd /home/aigent/kurtosis-cdk/snapshots/cdk-20260203-083342
./start-snapshot.sh
```

To stop the snapshot:
```bash
./stop-snapshot.sh
```
