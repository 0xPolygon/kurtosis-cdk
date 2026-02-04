# Summary JSON Documentation

## Overview

Each snapshot now includes a `summary.json` file that provides a comprehensive overview of all networks, services, contracts, and accounts in the snapshot. This file serves as a single source of truth for understanding the snapshot's configuration.

## Location

The `summary.json` file is generated in the root of each snapshot directory:
```
snapshots/<ENCLAVE>-<TIMESTAMP>/summary.json
```

## Structure

The summary.json contains the following top-level sections:

### 1. Metadata
```json
{
  "snapshot_name": "enclave-20240204-120000",
  "enclave": "my-enclave",
  "created_at": "2024-02-04T12:00:00Z"
}
```

### 2. Networks

#### L1 Network
```json
{
  "networks": {
    "l1": {
      "chain_id": "271828",
      "snapshot_block": {
        "number": "1000",
        "hash": "0xabcd..."
      },
      "genesis_hash": "0x0000...",
      "contracts": {},
      "services": { ... },
      "accounts": [ ... ]
    }
  }
}
```

**L1 Services include:**
- `geth` - Execution client (HTTP RPC, WebSocket, Engine API, Metrics)
- `beacon` - Beacon chain client (HTTP API, Metrics)
- `validator` - Validator client (Metrics)

**L1 Accounts include:**
- All pre-funded genesis accounts
- Validator public keys

#### Agglayer (Optional)
```json
{
  "networks": {
    "agglayer": {
      "contracts": {
        "rollup_manager": "0x1111...",
        "global_exit_root_v2": "0x2222..."
      },
      "services": { ... },
      "accounts": [ ... ]
    }
  }
}
```

**Agglayer Services include:**
- `grpc_rpc` - gRPC RPC endpoint
- `read_rpc` - Read RPC endpoint
- `admin_api` - Admin API endpoint
- `metrics` - Prometheus metrics

**Agglayer Accounts include:**
- Aggregator account (from aggregator.keystore)

#### L2 Networks (Optional)
```json
{
  "networks": {
    "l2_networks": {
      "001": {
        "chain_id": "2151908",
        "contracts": {
          "system_config": "0x4444...",
          "l1_bridge": "0x6666...",
          "l2_bridge": "0x9999...",
          "rollup_manager": "0x7777...",
          "global_exit_root": "0x8888..."
        },
        "services": { ... },
        "accounts": [ ... ]
      }
    }
  }
}
```

**L2 Services include:**
- `op-geth` - L2 execution client (HTTP RPC, WebSocket, Engine API)
- `op-node` - L2 consensus/rollup client (RPC, Metrics)
- `aggkit` - AggSender and AggOracle (RPC, REST API) [if present]

**L2 Accounts include:**
- Pre-funded genesis accounts
- Sequencer account
- AggOracle account
- Sovereign Admin account
- Claim Sponsor account

### 3. Service URLs

All services have two URL formats:

- **Internal**: For use within the Docker network (container-to-container)
  ```json
  "internal": "http://geth:8545"
  ```

- **External**: For access from the host machine
  ```json
  "external": "http://localhost:8545"
  ```

### 4. Account Information

Each account entry includes:

```json
{
  "address": "0x1234...",
  "private_key": "(encrypted in keystore)",
  "description": "Account role and purpose"
}
```

**Note**: Private keys in keystores are encrypted. The actual private keys can be accessed using the keystore files with the appropriate decryption tools.

For genesis accounts, the balance is also included:
```json
{
  "address": "0x1234...",
  "balance": "0x200000000000000000000",
  "description": "L1 pre-funded account"
}
```

### 5. Contract Addresses

Contract addresses are extracted from configuration files and vary by network:

**L1**: Currently no contracts (may be added in future)

**Agglayer**:
- `rollup_manager` - Rollup Manager contract
- `global_exit_root_v2` - Global Exit Root V2 contract

**L2 Networks**:
- `system_config` - System configuration contract
- `l1_bridge` - L1 bridge contract address
- `l2_bridge` - L2 bridge contract address
- `rollup_manager` - Rollup Manager contract
- `global_exit_root` - Global Exit Root contract

## Port Mapping for L2 Networks

L2 networks use a consistent port mapping scheme based on their network prefix:

```
Base Port = 10000 + (Network_Prefix * 1000)
```

For example, network `001`:
- HTTP RPC: 10000 + 1*1000 + 545 = 11545
- WebSocket: 10000 + 1*1000 + 546 = 11546
- Engine API: 10000 + 1*1000 + 551 = 11551
- Op-node RPC: 10000 + 1*1000 + 547 = 11547
- Op-node Metrics: 10000 + 1*1000 + 300 = 11300
- AggKit RPC: 10000 + 1*1000 + 576 = 11576
- AggKit REST: 10000 + 1*1000 + 577 = 11577

Network `002` would use base port 12000, etc.

## Usage Examples

### View the entire summary
```bash
cat summary.json | jq
```

### Get L1 RPC URL
```bash
jq -r '.networks.l1.services.geth.http_rpc.external' summary.json
# Output: http://localhost:8545
```

### List all L1 accounts
```bash
jq -r '.networks.l1.accounts[] | .address + " - " + .description' summary.json
```

### Get L2 network 001 bridge addresses
```bash
jq -r '.networks.l2_networks["001"].contracts | "L1 Bridge: \(.l1_bridge)\nL2 Bridge: \(.l2_bridge)"' summary.json
```

### List all services for L2 network 001
```bash
jq -r '.networks.l2_networks["001"].services | to_entries[] | .key' summary.json
# Output: op-geth, op-node, aggkit
```

### Get Agglayer Rollup Manager address
```bash
jq -r '.networks.agglayer.contracts.rollup_manager' summary.json
```

## Integration with Scripts

The summary.json is automatically generated during the snapshot process in Step 5 (after metadata generation). It requires:

- `discovery.json` - Container discovery information
- `metadata/checkpoint.json` - Snapshot checkpoint data
- `artifacts/genesis.json` - L1 genesis file
- `config/agglayer/config.toml` - Agglayer configuration (if present)
- `config/<prefix>/rollup.json` - L2 rollup configs (if present)
- `config/<prefix>/aggkit-config.toml` - L2 AggKit configs (if present)
- Various keystore files for account information

## Notes

1. **Null Values**: Some fields may be `null` if the information could not be extracted from configuration files. This is normal and does not indicate an error.

2. **Encrypted Keys**: Private keys stored in keystore files are encrypted. The `summary.json` indicates this with the value `"(encrypted in keystore)"`. To use these keys, access the keystore files directly with appropriate tooling.

3. **Internal vs External URLs**: Always use internal URLs when writing code that runs inside Docker containers. Use external URLs when accessing services from your host machine.

4. **Account Roles**: The `description` field for each account explains its role and purpose in the network. This helps identify which accounts need funding, which have special permissions, etc.

## Programmatic Access

The summary.json file is designed to be easily parsable by scripts and tools. Example use cases:

- **CI/CD**: Extract service URLs for automated testing
- **Monitoring**: Get metrics endpoints for setting up dashboards
- **Account Management**: Identify which accounts need funding
- **Contract Interaction**: Get contract addresses for deployment scripts
- **Documentation**: Generate network documentation automatically

## Troubleshooting

If `summary.json` is missing or incomplete:

1. Check the snapshot logs for errors during summary generation
2. Verify all required configuration files are present in the snapshot
3. Ensure the snapshot was created with the latest version of the snapshot scripts
4. Re-run the snapshot process if necessary

To regenerate just the summary.json:
```bash
./snapshot/scripts/generate-summary.sh <discovery.json> <snapshot-dir>
```
