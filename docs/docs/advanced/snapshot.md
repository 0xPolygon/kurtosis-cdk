---
sidebar_position: 7
title: "Kurtosis CDK Snapshot Tool"
description: "Create and restore deterministic snapshots of Kurtosis-managed Ethereum L1 devnets"
---

# Ethereum Kurtosis CDK Snapshot Tool

A reusable, fully scripted snapshot system for Kurtosis CDK devnets

## Overview

This tool creates deterministic, repeatable snapshots of am enclave that can be:
- Triggered at any time to freeze and capture L1 state
- Packaged into Docker images with state baked in
- Reproduced via Docker Compose to resume from exact state

## Prerequisites for Snapshot Creation

**IMPORTANT:** For snapshots to work correctly, the source enclave must meet these requirements:

### Agglayer Settlement Constraint
- **L2 networks must NOT have settled any transactions through the agglayer**
- Snapshots capture the L1 state at a specific point in time, but do not capture the agglayer's internal settlement state
- If the agglayer has processed settlements that are reflected on L1, restarting from the snapshot will cause inconsistencies (as the agglayer can not recover by just syncing L1)

### Recommended Enclave Configuration
To ensure clean snapshots:
- ✅ **DO:** Use enclaves without activity after initial setup
- ✅ **DO:** Snapshot immediately after deployment before running workloads
- ❌ **AVOID:** Using the bridge spammer before taking a snapshot
- ❌ **AVOID:** Running any cross-chain bridge transactions before snapshotting
- ❌ **AVOID:** Any agglayer settlement activity

If you need to test bridge functionality, do so **after** taking the snapshot, not before.

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
    ├── config/                # Configuration files for all services
    │   ├── agglayer/         # Agglayer config (if present)
    │   └── 001/, 002/, ...   # L2 network configs (if present)
    ├── docker-compose.yml    # Main compose file
    ├── summary.json          # Network summary (contracts, URLs, accounts)
    └── snapshot.log          # Execution log
```

**Note:** Temporary files (datadirs/, artifacts/, images/, metadata/, discovery.json, etc.) are automatically removed after snapshot generation to keep the output clean and ready for distribution.

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

### Agglayer state mismatch / Bridge issues after snapshot restoration
**Symptom:** After restoring a snapshot, bridge transactions fail or agglayer shows inconsistent state

**Cause:** The source enclave had agglayer settlements or bridge activity before the snapshot was taken

**Solution:**
- Recreate the snapshot from a clean enclave without any bridge/agglayer activity
- Ensure no bridge spammer or cross-chain transactions were run before snapshotting
- See "Prerequisites for Snapshot Creation" section above for proper enclave preparation

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
10. **Cleanup**: Remove temporary files (datadirs, artifacts, images, metadata, helper scripts)

**Important**:
- The snapshot process temporarily stops the L1 containers to ensure consistent state capture, but automatically restarts them afterward. This allows the original enclave to continue producing blocks while the snapshot artifacts are being prepared.
- Verification is performed automatically at the end, testing that the snapshot can boot and produce blocks. This adds 1-2 minutes to the snapshot process but ensures quality.
- After verification, all temporary and intermediate files are automatically cleaned up, leaving only the essential files needed to run the snapshot.
