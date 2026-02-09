# Quick Start Guide

Get started with Kurtosis CDK snapshots in 5 minutes.

## Prerequisites

- Docker and docker-compose installed
- Kurtosis CLI installed (for snapshot creation only)
- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash`)

## Step 1: Enable Debug API

When creating your Kurtosis enclave, enable debug API on geth:

**params.yaml**:
```yaml
participants:
  - el_type: geth
    el_extra_params:
      - "--http.api=eth,net,web3,debug,txpool"
    cl_type: lighthouse
```

Start the enclave:
```bash
kurtosis run --enclave my-enclave . --args-file params.yaml
```

## Step 2: Wait for Blocks

Let the chain run for a bit to build up some state:

```bash
# Check block number
GETH_RPC=$(kurtosis port print my-enclave el-1-geth-lighthouse rpc | grep -oE 'http://[^[:space:]]+')
cast block-number --rpc-url $GETH_RPC

# Wait until block > 10
```

## Step 3: Create Snapshot

```bash
cd /path/to/kurtosis-cdk
./snapshot/snapshot.sh my-enclave --out ./snapshots/
```

This will:
1. Build the init container image (first time only, ~2 minutes)
2. Discover geth RPC endpoint
3. Extract chainId from chain
4. Dump state via debug_dumpBlock
5. Generate all configs and scripts
6. Package everything in `./snapshots/snapshot-my-enclave-TIMESTAMP/`

**Duration**: 1-5 minutes depending on state size.

## Step 4: Run the Snapshot

```bash
cd ./snapshots/snapshot-my-enclave-*/
./up.sh
```

This will:
1. Clean runtime directory
2. Start init container (generates fresh genesis)
3. Start geth (initializes from genesis)
4. Start lighthouse beacon (syncs from geth)
5. Start lighthouse validator (produces blocks)

**Wait**: 60-120 seconds for chain to start producing blocks.

## Step 5: Verify

Check if chain is producing blocks:

```bash
# Block number should increase
cast block-number --rpc-url http://localhost:8545

# Wait 10 seconds
sleep 10

# Check again
cast block-number --rpc-url http://localhost:8545

# Get latest block details
cast block latest --rpc-url http://localhost:8545
```

## Step 6: Stop

```bash
docker-compose down
```

## Run Again (Fresh Genesis!)

The magic of stateless snapshots - just run again:

```bash
./up.sh
```

Every run generates a **fresh genesis with current timestamp**. No time-based limitations!

## Troubleshooting

### Error: "debug_dumpBlock does not exist"

You forgot to enable debug API. See Step 1.

### Error: "Enclave not found"

Check enclave name:
```bash
kurtosis enclave ls
```

### Chain not producing blocks

Check logs:
```bash
docker-compose logs -f
```

Look for errors in geth or lighthouse logs.

### Services not starting

Check service status:
```bash
docker-compose ps
```

If init failed:
```bash
docker-compose logs init
```

## Advanced Usage

### Custom Service Name

If your geth service has a different name:

```bash
GETH_SVC=my-geth-service PORT_ID=http ./snapshot/snapshot.sh my-enclave
```

### Multiple Runs

Test statelessness:

```bash
# First run
./up.sh
# Wait for blocks, check genesis time
docker-compose logs init | grep "Genesis time"

# Stop and run again
docker-compose down
./up.sh
# Check genesis time again - it should be different!
docker-compose logs init | grep "Genesis time"
```

### Following Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f geth
docker-compose logs -f lighthouse-bn
docker-compose logs -f lighthouse-vc
```

### Checking Beacon Sync

```bash
curl http://localhost:5052/eth/v1/node/syncing | jq
```

Should show:
```json
{
  "data": {
    "is_syncing": false,
    "is_optimistic": false
  }
}
```

## Next Steps

- Read [README.md](README.md) for detailed documentation
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
- Run tests: `./snapshot/tests/test_dump_to_alloc.py`
- Run E2E test: `./snapshot/tests/test_e2e.sh`

## RPC Endpoints

When snapshot is running:

- **Geth HTTP RPC**: http://localhost:8545
- **Geth WebSocket**: ws://localhost:8546
- **Geth Engine API**: http://localhost:8551
- **Lighthouse Beacon API**: http://localhost:5052

## Example Commands

```bash
# Get account balance
cast balance 0x1111111111111111111111111111111111111111 --rpc-url http://localhost:8545

# Send transaction
cast send 0x2222222222222222222222222222222222222222 \
  --value 1ether \
  --private-key 0x... \
  --rpc-url http://localhost:8545

# Call contract
cast call 0xCONTRACT "function()" --rpc-url http://localhost:8545

# Get transaction receipt
cast receipt 0xTXHASH --rpc-url http://localhost:8545

# Get logs
cast logs --from-block 0 --to-block latest --rpc-url http://localhost:8545
```

## Tips

1. **Snapshot early**: Create snapshots with less state for faster init
2. **Check logs**: Use `docker-compose logs -f` to follow startup
3. **Wait patiently**: First block takes 60-120 seconds
4. **Clean restarts**: Use `docker-compose down -v` for full cleanup
5. **Port conflicts**: Stop other chains before starting snapshot

## FAQ

**Q: How long can I wait before running a snapshot?**

A: Forever! There are no time-based limitations. Snapshots work days, weeks, or months after creation.

**Q: Do snapshots preserve transaction history?**

A: No, only final state (balances, nonces, code, storage). Transactions are not captured.

**Q: Can I run multiple snapshots simultaneously?**

A: Yes, but change port bindings in docker-compose.yml to avoid conflicts.

**Q: Why does init take so long?**

A: Genesis generation takes 30-60 seconds, longer for large state. This is normal.

**Q: Can I use this in production?**

A: Not recommended. This uses test mnemonics and has no security hardening. For development/testing only.

**Q: How do I update the validator mnemonic?**

A: Edit `val/mnemonics.yaml` in the snapshot directory before running.

**Q: What if geth RPC is on a different port?**

A: Override with environment variable: `PORT_ID=http ./snapshot/snapshot.sh my-enclave`

---

**Need help?** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or open a GitHub issue.
