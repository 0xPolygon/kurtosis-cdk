# Ethereum L1 Snapshot Tool - Quick Start

## TL;DR

```bash
# Create snapshot
./snapshot/snapshot.sh snapshot-test

# Verify snapshot
./snapshot/verify.sh snapshots/snapshot-test-<TIMESTAMP>/
```

## What This Tool Does

Creates a **complete, reproducible snapshot** of your Ethereum L1 devnet by:

1. Discovering Geth, Lighthouse Beacon, and Lighthouse Validator containers
2. Stopping them cleanly to ensure consistent state
3. Extracting all datadirs (execution, consensus, validator)
4. Building Docker images with state baked in
5. Generating Docker Compose for easy reproduction

## Prerequisites

- Docker (running)
- Kurtosis CLI
- Running Kurtosis enclave with L1 services
- Standard Unix tools: `jq`, `curl`, `tar`

## Basic Usage

### 1. Create a Snapshot

```bash
./snapshot/snapshot.sh <ENCLAVE_NAME>
```

**Example:**
```bash
./snapshot/snapshot.sh snapshot-test
```

This creates a timestamped directory in `snapshots/` with:
- Extracted state tarballs
- Docker images
- docker-compose.yml
- Helper scripts
- Full logs

### 2. Start the Snapshot

```bash
cd snapshots/snapshot-test-<TIMESTAMP>/
./start-snapshot.sh
```

Or manually:
```bash
docker-compose -f docker-compose.snapshot.yml up -d
```

### 3. Verify It Works

```bash
./snapshot/verify.sh snapshots/snapshot-test-<TIMESTAMP>/
```

This automated verification:
- Starts the snapshot
- Checks initial block number
- Waits and verifies blocks are progressing
- Reports pass/fail

### 4. Query State

```bash
cd snapshots/snapshot-test-<TIMESTAMP>/
./query-state.sh
```

Or use curl directly:
```bash
# Get block number
curl -s http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq

# Get beacon head
curl -s http://localhost:4000/eth/v1/beacon/headers/head | jq
```

### 5. Stop the Snapshot

```bash
cd snapshots/snapshot-test-<TIMESTAMP>/
./stop-snapshot.sh
```

Or manually:
```bash
docker-compose -f docker-compose.snapshot.yml down
```

## Advanced Usage

### Custom Output Directory

```bash
./snapshot/snapshot.sh snapshot-test --out ./my-snapshots
```

### Custom Image Tag

```bash
./snapshot/snapshot.sh snapshot-test --tag v1.0.0
```

This creates images tagged as:
- `snapshot-geth:snapshot-test-<TIMESTAMP>-v1.0.0`
- `snapshot-beacon:snapshot-test-<TIMESTAMP>-v1.0.0`
- `snapshot-validator:snapshot-test-<TIMESTAMP>-v1.0.0`

## File Structure

Each snapshot creates:

```
snapshots/snapshot-test-20260202-115500/
├── datadirs/
│   ├── geth.tar                      # Geth execution data
│   ├── lighthouse_beacon.tar         # Beacon consensus data
│   └── lighthouse_validator.tar      # Validator + slashing protection
├── artifacts/
│   ├── genesis.json                  # Genesis configuration
│   ├── chain-spec.yaml               # Beacon chain spec
│   ├── jwt.hex                       # JWT secret for Engine API
│   └── validator-keys/               # Validator keystores
├── metadata/
│   ├── checkpoint.json               # Block number, hashes, versions
│   └── manifest.sha256               # SHA256 checksums
├── images/
│   ├── geth/Dockerfile               # Geth image build
│   ├── beacon/Dockerfile             # Beacon image build
│   ├── validator/Dockerfile          # Validator image build
│   └── IMAGE_INFO.json               # Image metadata
├── docker-compose.snapshot.yml       # Main compose file
├── start-snapshot.sh                 # Helper: start services
├── stop-snapshot.sh                  # Helper: stop services
├── query-state.sh                    # Helper: query L1 state
├── SNAPSHOT_INFO.txt                 # Human-readable summary
├── SNAPSHOT_SUMMARY.txt              # Quick reference
├── USAGE.md                          # Detailed usage guide
└── snapshot.log                      # Full execution log
```

## Key Features

### 🔒 Safe & Reliable
- Graceful container shutdown
- Validates all state before extraction
- **Preserves critical slashing_protection.sqlite**
- Fails loudly on missing validators

### 📦 Self-Contained
- State baked into Docker images
- No external volumes required
- Reproducible on any Docker host

### 🔄 Idempotent
- Re-running creates new snapshot
- Never modifies existing snapshots
- Timestamped directories prevent conflicts

### ✅ Verified
- Automated verification script
- Tests block progression
- Checks service health

## Exposed Ports

When running a snapshot:

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 8545 | Geth | HTTP | JSON-RPC |
| 8546 | Geth | WS | WebSocket RPC |
| 8551 | Geth | HTTP | Engine API (authenticated) |
| 30303 | Geth | TCP/UDP | P2P discovery |
| 4000 | Beacon | HTTP | Beacon API |
| 9000 | Beacon | TCP/UDP | P2P discovery |
| 9001 | Geth | HTTP | Prometheus metrics |
| 5054 | Beacon | HTTP | Prometheus metrics |
| 5064 | Validator | HTTP | Prometheus metrics |

## Troubleshooting

### "No containers found"
- Check enclave is running: `kurtosis enclave ls`
- Verify container names: `docker ps | grep lighthouse`

### "Failed to extract datadir"
- Check disk space: `df -h`
- Ensure Docker has permissions
- Review logs: `tail snapshots/*/snapshot.log`

### "Validator not found"
**Validators are mandatory.** The tool will fail if validator container is missing. This is by design.

### "Port already in use"
Stop conflicting services:
```bash
# Check what's using ports
netstat -tuln | grep -E '8545|4000|9000'

# Stop Kurtosis enclave if running
kurtosis enclave stop <ENCLAVE_NAME>
```

### "Blocks not progressing"
Check validator logs:
```bash
docker logs snapshot-validator
```

Ensure validator has correct keys and slashing protection database.

## Maintenance

### List All Snapshots
```bash
ls -lh snapshots/
```

### Clean Old Snapshots
```bash
# Remove snapshots older than 7 days
find snapshots/ -name '*-202*' -mtime +7 -exec rm -rf {} \;
```

### List Snapshot Images
```bash
docker images | grep snapshot-
```

### Remove Old Images
```bash
# Remove specific tag
docker rmi snapshot-geth:snapshot-test-20260202-115500

# Remove all snapshot images
docker images | grep snapshot- | awk '{print $3}' | xargs docker rmi
```

## Best Practices

### When to Snapshot
- ✅ After important contract deployments
- ✅ Before major testing phases
- ✅ At regular intervals for backup
- ✅ After successfully completing transactions

### Naming Conventions
Use meaningful tags for important snapshots:
```bash
./snapshot/snapshot.sh my-enclave --tag post-deployment
./snapshot/snapshot.sh my-enclave --tag pre-migration
./snapshot/snapshot.sh my-enclave --tag stable-v1
```

### Storage Management
Snapshots can be large (several GB). Plan accordingly:
- Archive old snapshots to external storage
- Keep only recent/important snapshots locally
- Document what each snapshot represents

## Support

For issues or questions:
1. Check the logs: `snapshot.log`
2. Run verification: `./snapshot/verify.sh <DIR>`
3. Review container logs: `docker logs <container>`
4. Check the detailed README: `snapshot/README.md`

## Examples

### Complete Workflow

```bash
# 1. Create snapshot
./snapshot/snapshot.sh snapshot-test --tag v1.0.0

# 2. Stop original enclave (optional)
kurtosis enclave stop snapshot-test

# 3. Navigate to snapshot
cd snapshots/snapshot-test-20260202-115500/

# 4. Start snapshot
./start-snapshot.sh

# 5. Query state
./query-state.sh

# 6. Run verification
cd ../..
./snapshot/verify.sh snapshots/snapshot-test-20260202-115500/

# 7. Stop when done
cd snapshots/snapshot-test-20260202-115500/
./stop-snapshot.sh
```

### Continuous Monitoring

```bash
# Start snapshot
cd snapshots/snapshot-test-20260202-115500/
./start-snapshot.sh

# Monitor in real-time
watch -n 2 ./query-state.sh

# Or monitor logs
docker-compose -f docker-compose.snapshot.yml logs -f
```

## Technical Details

- **Base Images:** Uses same versions as original enclave
- **Data Paths:** Preserves exact directory structures
- **Networking:** Creates isolated bridge network
- **State:** Complete L1 state (execution + consensus + validator)
- **Security:** JWT authentication for Engine API maintained

## License

Part of kurtosis-cdk project.
