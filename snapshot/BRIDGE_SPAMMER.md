# Bridge Spammer Service

The snapshot docker-compose files now include an optional bridge spammer service that simulates blockchain activity by performing L1 to L2 and L2 to L1 bridge transactions.

## Overview

The bridge spammer service:
- Is **commented out by default** in the docker-compose.yml file
- Continuously performs bridge transactions between L1 and L2
- Helps test bridge functionality and generate realistic blockchain activity
- Based on the same bridge spammer used in Kurtosis CDK testing

## How to Enable

### 1. Generate a Snapshot

First, create a snapshot as usual:
```bash
cd /home/aigent/kurtosis-cdk
./snapshot/snapshot.sh
```

### 2. Navigate to Your Snapshot Directory

```bash
cd snapshots/<your-snapshot-id>
```

### 3. Uncomment the Bridge Spammer Service

Edit `docker-compose.yml` and find the bridge spammer section:

```yaml
# ==============================================================================
# Bridge Spammer Service (Optional - Commented Out)
# ==============================================================================
```

Uncomment all lines starting with `#  bridge-spammer-` (remove the `# ` prefix but keep the indentation).

### 4. Set Your Private Key

In the uncommented section, replace:
```yaml
- PRIVATE_KEY=YOUR_PRIVATE_KEY_HERE
```

with your actual private key (without the 0x prefix). **Important**: Ensure this wallet is funded on L1.

### 5. Verify the Bridge Script Path

The service expects the bridge script at:
```
../../static_files/additional_services/bridge-spammer/bridge.sh
```

If your snapshot is in a different location, update the volume mount path accordingly.

### 6. Start the Services

```bash
docker-compose up -d
```

## Configuration

The bridge spammer uses the following environment variables (automatically configured from snapshot metadata):

| Variable | Description | Example |
|----------|-------------|---------|
| `PRIVATE_KEY` | Wallet private key (without 0x) | Must be set by user |
| `L1_CHAIN_ID` | L1 chain ID | 271828 |
| `L1_RPC_URL` | L1 RPC endpoint | http://geth:8545 |
| `L2_CHAIN_ID` | L2 chain ID | 2151908 |
| `L2_RPC_URL` | L2 RPC endpoint | http://op-geth-001:8545 |
| `L2_NETWORK_ID` | L2 network ID for bridge | 1 |
| `L1_BRIDGE_ADDRESS` | L1 bridge contract | Extracted from config |
| `L2_BRIDGE_ADDRESS` | L2 bridge contract | Extracted from config |

## Behavior

Once started, the bridge spammer will:

1. **Initial Deposit**: Deposit 1 ETH from L1 to L2 to ensure sufficient balance
2. **Wait for Finalization**: Wait for the L1 block to be finalized
3. **Continuous Bridging**: 
   - Bridge from L1 to L2 (wait 60 seconds)
   - Bridge from L2 to L1 (wait 1 second)
   - Repeat indefinitely

The amounts bridged are dynamic and based on the current timestamp (in wei).

## Monitoring

### View Logs

```bash
docker-compose logs -f bridge-spammer-001
```

### Check Wallet Balances

On L1:
```bash
cast balance YOUR_ADDRESS --rpc-url http://localhost:8545
```

On L2:
```bash
cast balance YOUR_ADDRESS --rpc-url http://localhost:10545
```

### Watch Bridge Activity

```bash
# Monitor L1 bridge contract events
cast logs --address 0xC8cbEBf950B9Df44d987c8619f092beA980fF038 --rpc-url http://localhost:8545

# Monitor L2 bridge contract events  
cast logs --address 0xC8cbEBf950B9Df44d987c8619f092beA980fF038 --rpc-url http://localhost:10545
```

## Troubleshooting

### Service Fails to Start

**Check dependencies**: Ensure L1 (geth, beacon) and L2 (op-geth, op-node) services are healthy:
```bash
docker-compose ps
```

**Verify private key**: Make sure the wallet is funded on L1.

### Bridge Transactions Failing

**Check RPC connectivity**:
```bash
docker-compose exec bridge-spammer-001 curl http://geth:8545
docker-compose exec bridge-spammer-001 curl http://op-geth-001:8545
```

**Check contract addresses**: Verify the bridge addresses in the docker-compose.yml match your deployment.

### Script Not Found

If you see errors about `/scripts/bridge.sh` not found:
1. Verify the volume mount path in docker-compose.yml
2. Ensure the bridge.sh script exists at the specified path
3. Check file permissions (should be readable)

## Security Notes

- **Never commit private keys**: Always use environment variables or secrets management
- **Use test wallets**: Only use wallets intended for testing
- **Monitor balances**: The service will continuously spend funds on gas and bridge fees
- **Resource limits**: Consider setting resource limits if running in production-like environments

## Implementation Details

The bridge spammer service mimics the behavior of the Kurtosis CDK bridge spammer component:
- Uses the `polycli ulxly bridge asset` command for bridging
- Implements error handling with continuous execution
- Logs all operations in JSON format
- Automatically funds the claim sponsor address on L2

For the original implementation, see:
`kurtosis-cdk/src/additional_services/bridge_spammer.star`
