# L1 Snapshot Genesis Hash Mismatch Fix

## Problem Summary

The L1 services (geth and lighthouse) were not producing blocks after snapshot restoration. Investigation revealed a **genesis hash mismatch**:

- **Geth genesis hash**: `0x8ae3d91...` (from merged genesis with contracts)
- **Lighthouse expected hash**: `0xf8b880b...` (from original genesis)

## Root Cause

The snapshot extraction process (extract-l1-state.sh) had two steps:

1. **Export state from finalized block** and merge it into a new genesis.json (for geth)
2. **Download original genesis files** including genesis.ssz (for lighthouse)

This created inconsistent genesis hashes:
- Geth initialized from **new merged genesis** (with contracts baked in) → new hash
- Lighthouse loaded **original genesis.ssz** (pre-deployment state) → old hash

When lighthouse sent fork choice updates to geth with the old hash, geth responded "Syncing" because it couldn't find that block, causing the chain to stall.

## Solution: Datadir Extraction Mode

Instead of trying to fix the genesis hash mismatch (which requires regenerating genesis.ssz), I implemented a **datadir extraction mode** that:

1. **Extracts actual database directories** from running geth/lighthouse services
2. **Preserves state consistency** - both services have matching genesis state
3. **Avoids genesis merging** - no hash mismatch possible

### Changes Made

#### 1. extract-l1-state.sh
- Added `--extraction-mode` parameter (default: "datadir")
- Implemented `extract_datadirs_mode()` function
- Extracts `/data/geth/execution-data/geth` from geth service
- Extracts `/data/lighthouse/beacon-data/beacon` from lighthouse service
- Creates manifest with `"extraction_method": "datadir"`

#### 2. build-l1-images.sh
- Updated `read_l1_manifest()` to detect extraction mode
- Sets `GETH_DATADIR` and `LIGHTHOUSE_DATADIR` based on mode
- In datadir mode: uses extracted database directories
- In genesis mode: uses temporary build directories with genesis.json

#### 3. Dockerfile Templates
- Updated `geth.Dockerfile.template` to support both modes
- Updated `lighthouse.Dockerfile.template` to support both modes
- Templates detect mode based on presence of files:
  - Genesis mode: `genesis.json` present → run `geth init`
  - Datadir mode: `geth/` directory present → copy database

### Trade-offs

**Datadir Mode (New Default)**
- ✅ Reliable - no genesis hash mismatch issues
- ✅ State consistency guaranteed
- ❌ Larger Docker images (includes full database)
- ❌ Slower to build (more data to copy)

**Genesis Mode (Legacy)**
- ✅ Smaller Docker images (just genesis file)
- ✅ Faster to build
- ❌ Complex genesis.ssz regeneration required
- ❌ Prone to hash mismatch issues

## Testing

To create a new snapshot with the fix:

```bash
# Clean up old snapshot
cd /home/aigent/kurtosis-cdk
rm -rf snapshot-output/
docker volume prune -f
docker image rm l1-geth:snapshot l1-lighthouse:snapshot 2>/dev/null || true

# Run snapshot with datadir mode (default)
./snapshot/scripts/snapshot.sh

# Or explicitly specify extraction mode
./snapshot/scripts/snapshot.sh --extraction-mode datadir
```

## Verification

After snapshot creation and docker-compose up, verify L1 is producing blocks:

```bash
# Check geth is producing blocks
docker logs l1-geth 2>&1 | grep -i "block"

# Check geth block number increasing
docker exec l1-geth geth attach --exec 'eth.blockNumber' /root/.ethereum/geth.ipc

# Check lighthouse is synced
docker logs l1-lighthouse 2>&1 | grep -E "(Synced|head_slot)"

# Verify no genesis hash mismatch errors
docker logs l1-geth 2>&1 | grep -i "forkchoice"
```

Expected behavior:
- ✅ Geth shows "Imported new potential chain segment" messages
- ✅ eth.blockNumber increases over time
- ✅ Lighthouse shows "Synced" with increasing head_slot
- ✅ No "unknown forkchoice head" errors in geth logs

## Future Improvements

1. **Optimize datadir extraction** - Only extract necessary database files
2. **Add compression** - Compress extracted datadirs to reduce image size
3. **Implement incremental snapshots** - Only update changed state
4. **Fix genesis mode** - Properly regenerate genesis.ssz using lcli tool
