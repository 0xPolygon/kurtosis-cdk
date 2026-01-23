# Snapshot Feature

## Overview

The snapshot feature creates a simplified snapshot of a Kurtosis environment that can run on docker-compose. The snapshot includes:
- L1 blockchain state (geth + beacon node) embedded in Docker images
- Multiple L2 networks (one of each sequencer type × consensus type combination)
- Configuration files for L2 components, AggKit, and Agglayer
- A docker-compose file to orchestrate everything

## Architecture

[To be documented in Step 12]

## Prerequisites

[To be documented in Step 12]

## Usage

[To be documented in Step 12]

## Directory Structure

- `src/snapshot/` - Starlark modules for snapshot orchestration
- `snapshot/scripts/` - Shell scripts for post-processing
- `snapshot/templates/` - Dockerfile and docker-compose templates
- `snapshot/utils/` - Helper scripts and utilities

## Implementation Status

- [x] Step 1: Directory structure and module skeleton
- [ ] Step 2: Integrate snapshot mode into main.star
- [ ] Step 3: Implement multi-network registration
- [ ] Step 4: Implement config artifact extraction
- [ ] Step 5: Implement L1 state extraction
- [ ] Step 6: Process extracted configs to static format
- [ ] Step 7: Create Docker image build scripts
- [ ] Step 8: Generate Docker Compose configuration
- [ ] Step 9: Configure Docker Compose for fresh L2 services
- [ ] Step 10: Add error handling and validation
- [ ] Step 11: Create user-facing entry point script
- [ ] Step 12: Create documentation
- [ ] Step 13: Add testing and verification
- [ ] Step 14: Integration and cleanup

## Troubleshooting

[To be documented in Step 12]

## L2 Service Initial Sync

### Overview

In snapshot mode, **L2 services start with empty data volumes** and perform an initial sync from L1 on first run. This is an intentional design decision that:

- Keeps snapshots smaller and simpler (no L2 state is captured or extracted)
- Ensures L2 services start from a clean state
- Allows services to sync from the captured L1 state automatically

### Expected Behavior

When you start the docker-compose environment for the first time:

1. **L1 services** (geth and lighthouse) start with their captured state from the snapshot
2. **L2 services** start with empty volumes and begin syncing from L1:
   - **CDK-Erigon**: Will sync blockchain data from L1
   - **OP-Geth**: Will sync blockchain data from L1
   - **CDK-Node**: Will sync consensus data from L1
   - **OP-Node**: Will sync consensus data from L1

### Sync Time

The initial sync time depends on:
- The size of the L1 state (number of blocks)
- The network speed between services
- The processing power of your system

For typical development snapshots with a few hundred blocks, sync should complete in minutes. For larger snapshots with thousands of blocks, sync may take longer.

### Verification

You can verify that services are syncing by:
- Checking service logs: `docker-compose logs -f <service-name>`
- Checking L2 RPC endpoints for block numbers
- Monitoring service health endpoints

### Important Notes

- **First run will be slower**: The initial sync is a one-time operation. Subsequent starts will be faster as services use their synced state.
- **Services depend on L1**: L2 services will wait for L1 to be ready before starting their sync.
- **No L2 state in snapshot**: The snapshot only captures L1 state. All L2 state is generated fresh on first run.

## Limitations

[To be documented in Step 12]
