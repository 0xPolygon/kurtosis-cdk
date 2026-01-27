# Snapshot Feature

## Overview

The snapshot feature creates a simplified snapshot of a Kurtosis environment that can run on docker-compose. The snapshot includes:
- L1 blockchain state (geth + beacon node) embedded in Docker images
- Multiple L2 networks (one of each sequencer type × consensus type combination)
- Configuration files for L2 components using AggKit only (no cdk-node) and Agglayer
- A docker-compose file to orchestrate everything

## Architecture

The snapshot creation process works in several stages:

### Stage 1: Kurtosis Deployment (L1 Only)

1. **L1 Deployment**: Deploys geth and lighthouse services using existing `l1_launcher.launch()` logic
2. **Contract Deployment**: Deploys agglayer contracts on L1 (first network only)
3. **Network Registration**: For each network in `snapshot_networks`:
   - Registers network via sovereign contracts
   - Generates configuration files WITHOUT starting services
   - Updates agglayer config incrementally
4. **L1 State Preparation**: Waits for L1 to reach finalized state, then stops services gracefully

### Stage 2: Post-Processing (After Kurtosis Completes)

1. **L1 State Extraction**: Extracts geth and lighthouse datadirs from stopped containers
2. **Config Processing**: Converts dynamic Kurtosis configs to static docker-compose format
3. **Image Building**: Builds Docker images containing L1 state
4. **Compose Generation**: Creates docker-compose.yml with all services configured

### Stage 3: Docker Compose Deployment

When you start the docker-compose environment:
- **L1 services** start with captured state (immediately ready)
- **L2 services** start fresh and sync from L1 (one-time initial sync)
- **Agglayer** starts with all networks configured
- **AggKit** uses SQLite for storage (no PostgreSQL needed)
- All services communicate via docker-compose networking

### Database Architecture

The snapshot feature does NOT require PostgreSQL. All services use lightweight, file-based storage:
- **AggKit**: Uses SQLite databases for all components (AggSender, AggOracle, ClaimSponsor)
- **L1 services**: Store state in mounted data directories
- **L2 services**: Start with empty volumes and sync from L1

This design keeps the snapshot lightweight and eliminates the need for a separate database server.

## Usage

### Quick Start

1. **Create a networks configuration file** (see [Network Configuration Format](#network-configuration-format)):

```bash
cat > networks.json <<EOF
{
  "networks": [
    {
      "sequencer_type": "cdk-erigon",
      "consensus_type": "rollup",
      "deployment_suffix": "-001",
      "l2_chain_id": 20201,
      "network_id": 1,
      "l2_sequencer_address": "0x5b06837A43bdC3dD9F114558DAf4B26ed49842Ed",
      "l2_sequencer_private_key": "0x183c492d0ba156041a7f31a1b188958a7a22eebadca741a7fe64436092dc3181",
      "l2_aggregator_address": "0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d",
      "l2_aggregator_private_key": "0x2857ca0e7748448f3a50469f7ffe55cde7299d5696aedd72cfe18a06fb856970",
      "l2_admin_address": "0xE34aaF64b29273B7D567FCFc40544c5B272F08ACc1",
      "l2_admin_private_key": "0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625",
      "l2_dac_address": "0x5951F5b2604c9B42E478d5e2B2437F44073eF9A6",
      "l2_dac_private_key": "0x85d836ee6ea6f48bae27b31535e6fc2eefe056f2276b9353aafb294277d8159b",
      "l2_claimsponsor_address": "0x635243A11B41072264Df6c9186e3f473402F94e9",
      "l2_claimsponsor_private_key": "0x986b325f6f855236b0b04582a19fe0301eeecb343d0f660c61805299dbf250eb",
      "l2_sovereignadmin_address": "0xc653eCD4AC5153a3700Fb13442Bcf00A691cca16",
      "l2_sovereignadmin_private_key": "0xa574853f4757bfdcbb59b03635324463750b27e16df897f3d00dc6bef2997ae0"
    }
  ]
}
EOF
```

2. **Run the snapshot creation script**:

```bash
./snapshot/scripts/snapshot.sh \
    --enclave-name snapshot \
    --output-dir ./snapshot-output \
    --networks ./networks.json
```

3. **Wait for completion** (this may take 10-30 minutes depending on L1 state size)

4. **Start the environment**:

```bash
cd snapshot-output
docker-compose up -d
```

5. **Check service status**:

```bash
docker-compose ps
docker-compose logs -f
```

### Detailed Usage

#### Basic Command

```bash
./snapshot/scripts/snapshot.sh \
    --enclave-name <enclave-name> \
    --output-dir <output-directory> \
    --networks <networks-json-file>
```

#### Options

- `--enclave-name NAME` (required): Kurtosis enclave name where snapshot will be created
- `--output-dir DIR` (required): Directory where snapshot artifacts will be written
- `--networks FILE` (optional): JSON file with network configurations (see format below)
- `--l1-wait-blocks N` (optional): Number of finalized blocks to wait before extracting L1 state (default: 10)
- `--args-file FILE` (optional): Pre-generated Kurtosis args file (will generate if not provided)
- `--cleanup-enclave` (optional): Clean up enclave after snapshot creation (default: false)
- `--skip-kurtosis` (optional): Skip Kurtosis run (for testing post-processing only)
- `-h, --help`: Show help message

### Advanced Usage

#### Customizing Docker Images

You can customize the Docker images used in the snapshot by modifying the generated docker-compose.yml or by using environment variables in post-processing scripts:

**Custom L1 Images:**
```bash
# Build with custom geth/lighthouse images
./snapshot/scripts/build-l1-images.sh \
    --output-dir ./snapshot-output \
    --geth-image ethereum/client-go:v1.17.0 \
    --lighthouse-image sigp/lighthouse:v8.1.0 \
    --geth-tag my-geth:snapshot \
    --lighthouse-tag my-lighthouse:snapshot
```

**Custom L2/Agglayer Images:**
```bash
# Generate compose with custom images
./snapshot/scripts/generate-compose.sh \
    --output-dir ./snapshot-output \
    --agglayer-image my-registry/agglayer:v1.0.0 \
    --aggkit-image my-registry/aggkit:v1.5.0
```

#### Custom Port Allocation

Ports are automatically allocated, but you can customize them by editing `port-mapping.json` after config processing:

```bash
# After snapshot creation, edit port-mapping.json
cd snapshot-output
vim port-mapping.json  # Adjust port assignments
# Regenerate compose with custom ports
../snapshot/scripts/generate-compose.sh --output-dir .
```

#### Using Pre-Generated Args Files

For advanced use cases, you can generate the Kurtosis args file manually:

```bash
# Create args file with snapshot_mode enabled
cat > snapshot-args.json <<EOF
{
  "snapshot_mode": true,
  "snapshot_networks": [
    {
      "sequencer_type": "cdk-erigon",
      "consensus_type": "rollup",
      ...
    }
  ],
  "l1_chain_id": 1337,
  "l1_wait_blocks": 20,
  ...
}
EOF

# Use pre-generated args file
./snapshot/scripts/snapshot.sh \
    --enclave-name snapshot \
    --output-dir ./snapshot-output \
    --args-file ./snapshot-args.json
```

#### Skipping Specific Steps for Testing

You can skip the Kurtosis run to test post-processing only:

```bash
# Skip Kurtosis (useful for testing post-processing scripts)
./snapshot/scripts/snapshot.sh \
    --enclave-name snapshot \
    --output-dir ./snapshot-output \
    --skip-kurtosis \
    --networks ./networks.json
```

**Note:** This requires that L1 state and config artifacts already exist from a previous run.

#### Customizing L1 Wait Blocks

Control how many finalized blocks to wait before extracting L1 state:

```bash
# Wait for 20 finalized blocks (more conservative)
./snapshot/scripts/snapshot.sh \
    --enclave-name snapshot \
    --output-dir ./snapshot-output \
    --networks ./networks.json \
    --l1-wait-blocks 20
```

**Recommendations:**
- **Development**: 5-10 blocks (faster, less conservative)
- **Production**: 15-20 blocks (more conservative, ensures stability)
- **Large networks**: 20+ blocks (for high-throughput scenarios)


## Network Configuration Format

The network configuration is a JSON file with the following structure:

```json
{
  "networks": [
    {
      "sequencer_type": "cdk-erigon" | "op-geth",
      "consensus_type": "rollup" | "cdk-validium" | "pessimistic" | "ecdsa-multisig" | "fep",
      "deployment_suffix": "-001",
      "l2_chain_id": 20201,
      "network_id": 1,
      "l2_sequencer_address": "0x...",
      "l2_sequencer_private_key": "0x...",
      "l2_aggregator_address": "0x...",
      "l2_aggregator_private_key": "0x...",
      "l2_admin_address": "0x...",
      "l2_admin_private_key": "0x...",
      "l2_dac_address": "0x...",
      "l2_dac_private_key": "0x...",
      "l2_claimsponsor_address": "0x...",
      "l2_claimsponsor_private_key": "0x...",
      "l2_sovereignadmin_address": "0x...",
      "l2_sovereignadmin_private_key": "0x..."
    }
  ]
}
```

### Required Fields

#### Network Identification

- **`sequencer_type`** (string, required): Either `"cdk-erigon"` or `"op-geth"`
- **`consensus_type`** (string, required): One of:
  - For `cdk-erigon`: `"rollup"`, `"cdk-validium"`, `"pessimistic"`, `"ecdsa-multisig"`
  - For `op-geth`: `"rollup"`, `"pessimistic"`, `"ecdsa-multisig"`, `"fep"`
- **`deployment_suffix`** (string, required): Unique suffix for this network (e.g., `"-001"`, `"-002"`)
- **`l2_chain_id`** (integer, required): Unique L2 chain ID (must be > 0, e.g., `20201`, `20202`)
- **`network_id`** (integer, required): Unique network ID (must be > 0, e.g., `1`, `2`)

#### Address and Key Fields

All networks require the following address/private key pairs

- **`l2_sequencer_address`** (string, required): Ethereum address for sequencer (0x-prefixed hex)
- **`l2_sequencer_private_key`** (string, required): Private key for sequencer (0x-prefixed hex, 64 chars)
- **`l2_aggregator_address`** (string, required): Ethereum address for aggregator
- **`l2_aggregator_private_key`** (string, required): Private key for aggregator
- **`l2_admin_address`** (string, required): Ethereum address for admin
- **`l2_admin_private_key`** (string, required): Private key for admin
- **`l2_dac_address`** (string, required): Ethereum address for DAC (Data Availability Committee)
- **`l2_dac_private_key`** (string, required): Private key for DAC
- **`l2_claimsponsor_address`** (string, required): Ethereum address for claim sponsor
- **`l2_claimsponsor_private_key`** (string, required): Private key for claim sponsor
- **`l2_sovereignadmin_address`** (string, required): Ethereum address for sovereign admin
- **`l2_sovereignadmin_private_key`** (string, required): Private key for sovereign admin

### Validation Rules

1. **Uniqueness**: Each network must have unique:
   - `deployment_suffix`
   - `l2_chain_id`
   - `network_id`
   - All addresses (sequencer, aggregator, admin, etc.)

2. **Sequencer/Consensus Combinations**:
   - `cdk-erigon` supports: `rollup`, `cdk-validium`, `pessimistic`, `ecdsa-multisig`
   - `op-geth` supports: `rollup`, `pessimistic`, `ecdsa-multisig`, `fep`

3. **Address Format**: All addresses must be valid Ethereum addresses (0x-prefixed, 42 characters)
4. **Private Key Format**: All private keys must be valid hex strings (0x-prefixed, 66 characters)

### Using the Snapshot

1. **Navigate to output directory**:
   ```bash
   cd snapshot-output
   ```

2. **Start all services**:
   ```bash
   docker-compose up -d
   ```

3. **Check service status**:
   ```bash
   docker-compose ps
   ```

4. **View logs**:
   ```bash
   # All services
   docker-compose logs -f

   # Specific service
   docker-compose logs -f l1-geth
   docker-compose logs -f aggkit-1
   ```

5. **Stop services**:
   ```bash
   docker-compose down
   ```

6. **Access services**:
   - L1 RPC: `http://localhost:8545`
   - L2 RPC (network 1): `http://localhost:8123` (port varies by network)
   - Check `port-mapping.json` for all port assignments
