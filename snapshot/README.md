# Kurtosis CDK Snapshot System

A **stateless snapshot system** that captures blockchain state from a running Kurtosis enclave and produces a standalone docker-compose stack that **always starts from genesis with fresh timestamps**.

## Overview

This tool solves the problem of sharing blockchain state without time-based limitations. Traditional snapshots bake the genesis timestamp into the chain data, which means they become unusable after a certain period. This system uses **state baking** - it captures the full blockchain state and injects it into a fresh genesis that regenerates with the current timestamp on every run.

### Key Features

- ✅ **No time limitations** - snapshots work days/weeks/months after creation
- ✅ **Stateless** - no persisted data, fresh genesis on every run
- ✅ **Standalone** - runs with just Docker, no Kurtosis required
- ✅ **Deterministic** - same state dump = same chain state
- ✅ **Minimal** - 1 second slots, 5 second genesis delay
- ✅ **Complete** - includes EL (geth) + CL (lighthouse-bn) + VC (lighthouse-vc)

## How It Works

### Snapshot Creation (one-time)
1. Discovers geth RPC endpoint from running Kurtosis enclave
2. Extracts chainId via `eth_chainId`
3. Dumps full state via `debug_dumpBlock` (requires debug API enabled)
4. Converts state to genesis alloc format
5. Creates genesis template with TIMESTAMP_PLACEHOLDER
6. Creates CL config with minimal preset (1s or 2s slots)
7. Packages everything with docker-compose stack

### Runtime (every `docker-compose up`)
1. Init container generates fresh timestamp: `date +%s`
2. Patches EL genesis.json with current timestamp
3. Generates CL genesis.ssz via `eth2-testnet-genesis --timestamp`
4. Generates validator keystores from mnemonic
5. Geth initializes from fresh genesis
6. Lighthouse beacon syncs from geth via Engine API
7. Lighthouse validator produces blocks

## Requirements

- **Kurtosis CLI** (for snapshot creation only)
- **Docker** and **docker-compose**
- **Foundry** (`cast` command for RPC calls)
- **Python 3** (for state conversion)
- **Geth with debug API enabled** (source enclave must have `--http.api=eth,net,web3,debug`)

## Usage

### Create Snapshot

```bash
# Start a Kurtosis enclave (or use existing one)
kurtosis run --enclave my-enclave .

# Let it run to build up some state
# Then create snapshot:
./snapshot/snapshot.sh my-enclave --out ./snapshots/
```

**Environment Variables:**
- `GETH_SVC` - Geth service name (default: `el-1-geth-lighthouse`)
- `PORT_ID` - Port identifier (default: `rpc`)

Example with custom service:
```bash
GETH_SVC=my-geth-service PORT_ID=http ./snapshot/snapshot.sh my-enclave
```

### Run Snapshot

```bash
cd snapshots/snapshot-my-enclave-*
./up.sh

# Follow logs
docker-compose logs -f

# Check if chain is running
cast block-number --rpc-url http://localhost:8545

# Stop
docker-compose down
```

### Run Again (Fresh Genesis)

```bash
# Just run up.sh again - timestamps will be fresh!
./up.sh
```

Every time you run `./up.sh`, the init container generates a new genesis with the current timestamp. No time-based limitations!

## Directory Structure

```
snapshots/snapshot-ENCLAVE-TIMESTAMP/
├── el/
│   ├── state_dump.json           # Raw debug_dumpBlock output
│   ├── alloc.json                # Converted alloc
│   └── genesis.template.json     # Template with TIMESTAMP_PLACEHOLDER
├── cl/
│   └── config.yaml               # CL config (1s or 2s slots)
├── val/
│   └── mnemonics.yaml            # Validator mnemonic
├── tools/
│   ├── init.sh                   # Runtime init script
│   └── dump_to_alloc.py          # State conversion tool
├── runtime/                      # Generated at runtime (gitignored)
│   ├── jwt.hex                   # JWT secret
│   ├── el_genesis.json           # Patched genesis
│   └── cl/
│       └── genesis.ssz           # Generated CL genesis
├── docker-compose.yml            # Service orchestration
├── up.sh                         # Convenience wrapper
└── metadata.json                 # Snapshot metadata
```

## Services

### init
- **Image**: `kurtosis-cdk-snapshot-init:latest` (built during snapshot creation)
- **Purpose**: Generates fresh genesis with current timestamp
- **Runs**: On every `docker-compose up`, before other services

### geth
- **Image**: `ethereum/client-go:v1.16.8`
- **Ports**: 8545 (HTTP RPC), 8546 (WebSocket), 8551 (Engine API)
- **Data**: Ephemeral (container-local `/tmp/geth-data`)

### lighthouse-bn (Beacon Node)
- **Image**: `sigp/lighthouse:v8.1.0`
- **Ports**: 5052 (Beacon API)
- **Data**: Ephemeral (container-local `/tmp/lighthouse-bn`)

### lighthouse-vc (Validator Client)
- **Image**: `sigp/lighthouse:v8.1.0`
- **Data**: Ephemeral (container-local `/tmp/lighthouse-vc`)

## Testing

### Unit Tests

Test state conversion:
```bash
cd snapshot/tests
python3 test_dump_to_alloc.py
```

Test genesis template creation:
```bash
cd snapshot/tests
./test_genesis_template.sh
```

### Integration Test

End-to-end test (creates enclave, snapshot, runs it):
```bash
cd snapshot/tests
./test_e2e.sh
```

**Warning**: E2E test takes ~5-10 minutes and requires Kurtosis.

## Troubleshooting

### "debug namespace not enabled"

**Error**: `the method debug_dumpBlock does not exist/is not available`

**Solution**: Enable debug API on source geth. In Kurtosis params:
```yaml
participants:
  - el_type: geth
    el_extra_params:
      - "--http.api=eth,net,web3,debug,txpool"
```

### "Service not found"

**Error**: `kurtosis port print` returns empty

**Solution**: Override service name and port:
```bash
GETH_SVC=my-geth-service PORT_ID=http ./snapshot/snapshot.sh my-enclave
```

### "Init container failed"

**Error**: Init exits with non-zero code

**Check logs**:
```bash
docker-compose logs init
```

Common causes:
- Missing eth2-testnet-genesis binary (rebuild init image)
- Invalid config.yaml format
- Invalid genesis.template.json

### "Chain not producing blocks"

**Check**:
1. Geth healthy: `docker-compose ps`
2. Lighthouse beacon synced: `docker-compose logs lighthouse-bn`
3. JWT matches: `cat runtime/jwt.hex`

**Lighthouse sync**:
Beacon must sync from geth before validator can produce blocks. Check beacon logs for "execution client synced" message.

### "Lighthouse won't sync"

**Check**:
- Genesis.ssz exists: `ls -la runtime/cl/genesis.ssz`
- Config.yaml exists: `ls -la runtime/cl/config.yaml`
- JWT accessible: `cat runtime/jwt.hex`
- Geth Engine API responding: `curl http://localhost:8551`

## Architecture Details

### Why Stateless?

Traditional blockchain snapshots save the entire database (multi-GB) and require restoring with the exact original genesis timestamp. This creates time-based limitations - after a certain period, the snapshot becomes unusable because the chain's internal clock is too far behind.

This system uses **state baking**:
1. Extract all account state (balances, nonces, code, storage)
2. Inject into genesis alloc
3. Regenerate genesis with current timestamp on every run

Result: **No time limitations**. The snapshot works forever.

### Why Not Use eth2-testnet-genesis bellatrix?

The plan originally specified using `eth2-testnet-genesis bellatrix`, but the implementation uses `eth-genesis-state-generator beaconchain` (from Hive's ethereum-genesis-generator) because:
1. It's the standard toolchain used by ethereum-package
2. Better lighthouse compatibility
3. More actively maintained

### Timestamp Handling

**Critical**: The genesis timestamp must be:
1. **Integer** in genesis.json (not hex string like `"0x..."`)
2. **Current time** (not hardcoded)
3. **Consistent** between EL and CL

The init script uses:
```bash
GENESIS_TIME=$(date +%s)  # Unix timestamp as integer
jq --arg ts "$GENESIS_TIME" '.timestamp = ($ts | tonumber)' ...
```

### Validator Keys

Uses standard test mnemonic for reproducibility:
```
abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about
```

Generated via `eth2-val-tools` at runtime, producing lighthouse-compatible keystores.

## Limitations

- **Fresh timestamps**: Block timestamps will be current time, not original times
- **Fresh chain**: Chain starts from block 0, not original block numbers
- **Debug API required**: Source geth must have debug namespace enabled
- **State only**: Does not capture pending transactions or mempool

## Future Improvements

- [ ] Support for custom validator mnemonics
- [ ] Option to preserve original timestamps (time manipulation)
- [ ] Multi-validator support
- [ ] Automatic genesis optimization (pruning empty accounts)
- [ ] Support for other EL clients (besu, nethermind, etc.)
- [ ] Snapshot compression for faster transfers

## License

Same as parent project (kurtosis-cdk).

## Contributing

1. Run unit tests: `./snapshot/tests/test_dump_to_alloc.py`
2. Run genesis test: `./snapshot/tests/test_genesis_template.sh`
3. Run E2E test: `./snapshot/tests/test_e2e.sh`
4. Submit PR with description of changes

---

For questions or issues, open a GitHub issue in the kurtosis-cdk repository.
