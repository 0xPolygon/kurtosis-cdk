---
sidebar_position: 4
---

# Bridge UI

## Introduction

This configuration deploys the default [CDK OP Geth](./cdk-opgeth.md) setup enhanced with the [bridge hub API](https://github.com/agglayer/agglayer-bridge-hub-api) and its dedicated UI, called [Agglayer dev UI](https://github.com/agglayer/agglayer-dev-ui), providing a user-friendly browser interface for bridging assets between L1 and L2.

### What's Deployed?

- L1 Ethereum blockchain (lighthouse/geth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer) and [mock prover](https://github.com/agglayer/provers)).
- L2 Optimism blockchain (op-geth/op-node) enhanced with [AggKit](https://github.com/agglayer/aggkit) for seamless Agglayer connectivity.
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.
- Additional services:
  - [Bridge Hub API](https://github.com/agglayer/agglayer-bridge-hub-api): indexes bridge and claim transactions
  - [Agglayer Dev UI](https://github.com/agglayer/agglayer-dev-ui): for browser-based bridging

### Use Cases

- Development and testing of bridge functionality
- Easy asset transfers between L1 and L2 without CLI tools
- Demonstrating bridge capabilities to stakeholders

### Deployment

```yaml title="params.yml"
args:
  additional_services:
    - bridge_ui
```

To deploy this environment:

```bash
kurtosis run --enclave cdk --args-file params.yml .
```

After deployment, retrieve the server url:

```bash
kurtosis port print pos agglayer-dev-ui-proxy-001 http
```

Open the printed URL in your browser to access the interface and start bridging assets between L1 and L2.

## How to Bridge

The following example demonstrates bridging assets from L1 to L2. The process for bridging from L2 to L1 follows the same steps.

:::warning  
If you've redeployed the environment, MetaMask may have cached outdated RPC URLs. [Delete the old network configurations](#how-to-refresh-the-rpcs) and add the new ones before proceeding.  
:::

Step 1: Initiate the bridge
- Select the "Kurtosis L1" network
- Enter the amount of ether to bridge
- Click the "Bridge" button

![step-1](/img/bridge-ui/bridge/1.png)

Step 2: Add network to MetaMask
- When prompted, review the "Kurtosis L1" network details in MetaMask
- Click "Confirm" to add the network

![step-2](/img/bridge-ui/bridge/2.png)

Step 3: Confirm the transaction
- Review the bridge transaction details in MetaMask
- Verify the amount and destination
- Click "Confirm" to execute the transaction

![step-3](/img/bridge-ui/bridge/3.png)

Step 4: Transaction processing
- Wait for the transaction confirmation
- If the transaction fails, retry the operation
- For persistent failures, check the bridge-hub service logs for errors

![step-4](/img/bridge-ui/bridge/4.png)

Step 5: Verify completion
- Monitor your transaction status in the interface

![step-5](/img/bridge-ui/bridge/5.png)

## How to refresh the RPCs

If MetaMask can't fetch the chain ID, the RPC URL is likely outdated.

![step-1](/img/bridge-ui/rpc-issue/1.png)

Delete the outdated RPC URLs.
- Open MetaMask settings
- Navigate to Networks
- Delete the outdated "Kurtosis L1" and "Kurtosis L2" networks

![step-2](/img/bridge-ui/rpc-issue/2.png)
