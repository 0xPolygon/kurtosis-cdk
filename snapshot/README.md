# Ethereum L1 Snapshot Tool

A reusable, fully scripted snapshot system for Kurtosis-managed Ethereum L1 devnets (Geth + Lighthouse Beacon + Lighthouse Validator).

## Overview

This tool creates deterministic, repeatable snapshots of L1 state that can be:
- Triggered at any time to freeze and capture L1 state
- Packaged into Docker images with state baked in
- Reproduced via Docker Compose to resume from exact state

## Quick Start

```bash
# Create and verify snapshot of enclave (verification is automatic)
./snapshot/snapshot.sh <ENCLAVE_NAME>

# With custom output directory and tag
./snapshot/snapshot.sh snapshot-test --out ./my-snapshots --tag v1.0.0

# Manual verification (optional, already done during snapshot creation)
./snapshot/verify.sh snapshots/snapshot-test-<TIMESTAMP>/
```

## Directory Structure

Each snapshot creates a timestamped directory:

```
snapshots/
└── <ENCLAVE_NAME>-<TIMESTAMP>/
    ├── datadirs/              # Exported state
    │   ├── geth.tar
    │   ├── lighthouse_beacon.tar
    │   └── lighthouse_validator.tar
    ├── artifacts/             # Configuration files
    │   ├── genesis.json
    │   ├── chain-spec.yaml
    │   ├── bootnodes.txt
    │   └── jwt.hex
    ├── metadata/              # Snapshot metadata
    │   ├── checkpoint.json    # Block height, hash, versions
    │   └── manifest.sha256    # Checksums for all tarballs
    ├── images/                # Dockerfiles
    │   ├── geth/
    │   ├── beacon/
    │   └── validator/
    ├── docker-compose.snapshot.yml
    └── snapshot.log           # Execution log
```

## Requirements

- Docker (for container operations)
- Kurtosis CLI (for enclave discovery)
- jq (for JSON processing)
- curl (for RPC queries)
- tar (for datadir archiving)

## Architecture

### Data Directory Locations

**Geth (Execution Layer)**
- Container path: `/data/geth/execution-data/`
- Contains: `geth/`, `keystore/`, `geth.ipc`

**Lighthouse Beacon (Consensus Layer)**
- Container path: `/data/lighthouse/beacon-data/`
- Contains: `beacon/` (with `chain_db/`, `freezer_db/`, `network/`)

**Lighthouse Validator**
- Container paths:
  - `/root/.lighthouse/custom/` (validators/)
  - `/validator-keys/` (keys/, secrets/, slashing_protection.sqlite)
- **CRITICAL**: Must preserve `slashing_protection.sqlite`

### Container Naming Patterns

Kurtosis-managed containers follow this pattern:
- Geth: `el-1-geth-lighthouse--<UUID>`
- Beacon: `cl-1-lighthouse-geth--<UUID>`
- Validator: `vc-1-geth-lighthouse--<UUID>`

## Scripts

### snapshot.sh
Main orchestrator script. Coordinates the entire snapshot process.

**Usage:**
```bash
./snapshot/snapshot.sh <ENCLAVE_NAME> [--out <DIR>] [--tag <TAG>]
```

**Parameters:**
- `ENCLAVE_NAME`: Required. Name of the Kurtosis enclave to snapshot
- `--out`: Optional. Output directory (default: `snapshots`)
- `--tag`: Optional. Custom tag suffix for images

### verify.sh
Validates a snapshot by booting it and verifying block progression.

**Usage:**
```bash
./snapshot/verify.sh <SNAPSHOT_DIR>
```

**Checks:**
- Initial block number matches checkpoint
- Blocks continue to progress after boot
- All services are healthy

## Image Tags

Images are tagged with: `snapshot-{component}:{ENCLAVE}-{TIMESTAMP}[-{TAG}]`

Examples:
- `snapshot-geth:snapshot-test-20260202-115500`
- `snapshot-beacon:snapshot-test-20260202-115500`
- `snapshot-validator:snapshot-test-20260202-115500`

## Safety Features

- **Validator Check**: Fails immediately if no validator datadir found
- **Clean Shutdown**: Containers stopped gracefully before extraction
- **State Consistency**: All components frozen before extraction
- **Checksum Validation**: SHA256 manifest for all tarballs
- **Idempotent**: Re-running creates new snapshot, doesn't modify existing

## Troubleshooting

### No containers found
- Verify enclave is running: `kurtosis enclave ls`
- Check container names: `docker ps | grep lighthouse`

### Extraction failed
- Ensure containers are stopped: `docker ps`
- Check disk space: `df -h`
- Review logs: `tail snapshots/*/snapshot.log`

### Validator missing
- Validators are mandatory - snapshot will fail if not found
- Verify validator container exists before running snapshot

### Snapshot won't boot
- Check docker-compose logs: `docker-compose -f docker-compose.snapshot.yml logs`
- Verify image was built: `docker images | grep snapshot`
- Ensure ports are not in use: `netstat -tuln | grep -E '8545|4000'`

## Maintenance

### Cleanup old snapshots
```bash
# Remove snapshots older than 7 days
find snapshots/ -name '*-202*' -mtime +7 -exec rm -rf {} \;
```

### List all snapshot images
```bash
docker images | grep snapshot-
```

### Remove old snapshot images
```bash
docker images | grep snapshot- | awk '{print $3}' | xargs docker rmi
```

## Technical Details

### Snapshot Process Flow

1. **Discovery**: Locate containers by enclave name
2. **Pre-Stop Metadata**: Query current block number/hash
3. **Stop & Extract**: Gracefully stop all L1 containers and export datadirs to tarballs
4. **Resume Original Enclave**: Restart containers in original enclave to resume block production
5. **Metadata**: Generate checkpoint.json and checksums
6. **Build**: Create Docker images with baked-in state
7. **Compose**: Generate docker-compose.yml
8. **Finalization**: Create summary and log execution
9. **Verification**: Automatically start snapshot and verify it works correctly

**Important**:
- The snapshot process temporarily stops the L1 containers to ensure consistent state capture, but automatically restarts them afterward. This allows the original enclave to continue producing blocks while the snapshot artifacts are being prepared.
- Verification is performed automatically at the end, testing that the snapshot can boot and produce blocks. This adds 1-2 minutes to the snapshot process but ensures quality.

### Network Configuration

The generated Docker Compose creates a bridge network with:
- Geth RPC: `8545` (HTTP), `8546` (WS), `30303` (P2P)
- Beacon API: `4000` (HTTP), `9000` (P2P)
- Validator: No exposed ports (internal only)

### State Reproduction

Images contain complete state:
- No external volumes required
- All data baked into image layers
- JWT secret included for engine API auth
- Genesis and chain specs embedded

## License

Part of the kurtosis-cdk project.
