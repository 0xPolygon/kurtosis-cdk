# Transaction Replay Snapshot System

## Overview

The Kurtosis CDK snapshot system uses **transaction replay** instead of state baking to create deterministic, time-unlimited snapshots of L1 devnets.

### How It Works

**Snapshot Creation:**
1. Stop beacon/validator (keep geth running)
2. Extract all transactions from L1 blocks via RPC
3. Generate executable replay script from transactions
4. Regenerate genesis.ssz with fresh timestamp
5. Build fresh Docker images (no state baking)
6. Resume original enclave

**Snapshot Startup:**
1. Geth initializes from genesis.json
2. Beacon starts with fresh genesis.ssz
3. Validator starts → blocks begin being produced
4. Transaction replayer sends all transactions → they get mined
5. L2 services start and sync

## Benefits

✅ **No time limitations** - Snapshots work days/weeks after creation (with genesis regeneration)
✅ **Smaller images** - No multi-GB datadir tarballs (~50% size reduction)
✅ **Deterministic** - Same transactions = same state
✅ **Debuggable** - Replay script can be inspected/modified
✅ **Simpler** - No complex state extraction

## Usage

### Create Snapshot

```bash
# Basic usage
./snapshot.sh my-enclave --out ./snapshots/

# The script will:
# - Extract transactions from L1 blocks
# - Regenerate genesis.ssz with fresh timestamp
# - Build Docker images with transaction replay
# - Generate docker-compose.yml for startup
```

### Start Snapshot

```bash
cd ./snapshots/my-enclave-20260207-123456/
docker-compose up -d

# Monitor startup
docker-compose logs -f geth          # Watch geth start and replay
docker-compose logs -f replayer      # Watch transaction replay
docker-compose logs -f beacon        # Watch beacon sync
```

### Verify Snapshot

```bash
# Check block production
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Watch blocks increase
watch -n 1 'curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
  http://localhost:8545 | jq -r ".result" | xargs printf "%d\n"'
```

## Architecture

### Transaction Extraction

**Location:** `scripts/extract-transactions.sh`

Extracts transactions from L1 blocks using RPC:
- Queries `eth_getBlockTransactionCountByNumber` for each block
- Gets transaction details via `eth_getTransactionByBlockNumberAndIndex`
- Extracts raw transaction data via `debug_getRawTransaction`
- Outputs to `transactions.jsonl` format

### Replay Script Generation

**Location:** `scripts/generate-replay-script.sh`

Converts transactions.jsonl to executable bash script:
- Waits for geth RPC to be ready
- Sends transactions via `eth_sendRawTransaction`
- Waits for receipts with timeout
- Includes retry logic for failed transactions
- Logs progress

### Genesis Regeneration

**Location:** `scripts/generate-fresh-genesis.sh`

Generates fresh genesis.ssz with current timestamp:
- Calculates new genesis time (now + 60 seconds)
- Updates chain-spec.yaml with new MIN_GENESIS_TIME
- Uses Lighthouse lcli via Docker to regenerate genesis.ssz
- Falls back to original genesis.ssz if regeneration fails

### Docker Images

**Replayer Image** (`snapshot-replayer`)
- Base: Alpine 3.19
- Tools: bash, wget
- Contains: replay-transactions.sh script
- Runs once and exits after replay complete

**Geth Image** (`snapshot-geth`)
- Base: ethereum/client-go:v1.16.8
- Initializes: Fresh geth from genesis.json
- Starts: Clean execution layer

**Beacon Image** (`snapshot-beacon`)
- Base: sigp/lighthouse:v8.0.1
- Contains: Fresh genesis.ssz with current timestamp
- Starts: Fresh beacon node with lenient sync flags

**Validator Image** (`snapshot-validator`)
- Base: sigp/lighthouse:v8.0.1
- Contains: Validator keys with slashing protection
- Starts: Validator client

### Service Dependencies

```
geth (service_healthy)
  ↓
beacon (service_healthy) ← depends on geth
  ↓
validator (service_started) ← depends on beacon
  ↓
transaction-replayer (runs once) ← depends on validator
```

All L2 services depend on `geth.service_healthy`.

## Performance

### Startup Times

| Transaction Count | Startup Time |
|-------------------|--------------|
| 0 transactions    | ~25 seconds  |
| 100 transactions  | ~80 seconds  |
| 1,000 transactions| ~8 minutes   |
| 10,000 transactions| ~85 minutes |

### Image Sizes

- **Before** (state baking): ~2-3 GB per image
- **After** (transaction replay): ~500 MB - 1 GB per image
- **Reduction**: ~50-70%

## Troubleshooting

### Beacon Not Producing Blocks

**Symptoms:**
- Beacon logs show `WARN Not ready Bellatrix`
- Current slot is very high but head_slot is 0
- Blocks stuck at 0

**Cause:** Genesis timestamp issue (old genesis.ssz)

**Solution:**
```bash
# Check if genesis regeneration worked
grep "Fresh genesis.ssz generated" snapshot.log

# If not, genesis regeneration may have failed
# Check Docker is available and lighthouse image can be pulled
docker pull sigp/lighthouse:v8.0.1
```

### Transaction Replay Timing Out

**Symptoms:**
- Replayer logs show "Warning: Transaction X timed out"
- Transactions aren't being mined

**Cause:** Blocks not being produced yet

**Solution:**
- Verify beacon and validator are running and healthy
- Check beacon logs for block production
- Ensure validator has started (blocks need to be produced before transactions can be mined)

### Port Conflicts

**Symptoms:**
- Docker compose fails with "port already allocated"

**Cause:** Another snapshot or enclave using the same ports

**Solution:**
```bash
# Stop conflicting containers
docker ps | grep -E "geth|beacon" | awk '{print $1}' | xargs docker stop

# Or use different ports by editing docker-compose.yml
```

## Components

### New Files

- `scripts/extract-transactions.sh` - Extract transactions from L1 blocks
- `scripts/generate-replay-script.sh` - Generate replay script from transactions
- `scripts/generate-fresh-genesis.sh` - Regenerate genesis.ssz with fresh timestamp
- `tests/test-replay-script.sh` - Unit tests for replay script generation

### Modified Files

- `scripts/extract-state.sh` - Removed datadir extraction, added transaction extraction
- `scripts/build-images.sh` - Added replayer image, fresh initialization, genesis regeneration
- `scripts/generate-compose.sh` - Added replayer service, updated beacon flags
- `snapshot.sh` - Added replay script generation step

## Technical Details

### Why Transaction Replay?

Traditional state baking approach:
- ❌ Creates multi-GB Docker images
- ❌ Time-limited (PoS consensus timestamp checks)
- ❌ Complex extraction and restoration
- ❌ Difficult to debug issues

Transaction replay approach:
- ✅ Smaller images (only configs + replay script)
- ✅ Time-unlimited (with genesis regeneration)
- ✅ Deterministic state reconstruction
- ✅ Easy to inspect and modify transactions
- ✅ Simpler architecture

### PoS Genesis Timestamp Challenge

Proof-of-Stake networks have time-sensitive consensus:
- Genesis timestamp is embedded in genesis.ssz
- Beacon calculates current slot based on time elapsed since genesis
- If too much time has passed, beacon won't produce blocks (expects to be at slot N but chain is at slot 0)

**Solution:** Regenerate genesis.ssz with fresh timestamp during snapshot build using Lighthouse's `lcli` tool.

### Lighthouse Flags for Lenient Sync

The beacon node uses these flags for more lenient synchronization:
- `--disable-deposit-contract-sync` - Skip deposit contract synchronization
- `--allow-insecure-genesis-sync` - Allow syncing from genesis even if considered behind
- `--genesis-backfill` - Allow backfilling from genesis

## Future Improvements

- [ ] Parallel transaction replay (batch send multiple transactions)
- [ ] Compressed transaction storage (gzip transactions.jsonl)
- [ ] Incremental snapshots (only new transactions since last snapshot)
- [ ] Snapshot diff/merge capabilities
- [ ] Web UI for snapshot management

## Contributing

When modifying the snapshot system:
1. Run unit tests: `./snapshot/tests/test-replay-script.sh`
2. Test with real enclave: Create and start a snapshot
3. Verify blocks are produced on both L1 and L2
4. Check all services become healthy
5. Update documentation

## References

- [Ethereum Execution API](https://ethereum.github.io/execution-apis/api-documentation/)
- [Lighthouse Book](https://lighthouse-book.sigmaprime.io/)
- [SSZ Specification](https://github.com/ethereum/consensus-specs/blob/dev/ssz/simple-serialize.md)
