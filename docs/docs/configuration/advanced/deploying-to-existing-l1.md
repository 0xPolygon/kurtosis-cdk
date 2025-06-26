---
sidebar_position: 4
---

# Deploy Kurtosis CDK to an existing L1 like Sepolia

## Introduction

By default, Kurtosis CDK will deploy a local L1 based on the [ethereum-package](https://github.com/ethpandaops/ethereum-package), and all L1 contracts and interaction will be made to this local L1 within the enclave.
If you want to deploy Kurtosis CDK to an existing L1, whether it be a different local L1 for testing, or a public testnet like Sepolia, follow this guide.

### What's Deployed?

- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer), and [mock prover](https://github.com/agglayer/provers))
- L2 Optimism blockchain ([op-geth](https://github.com/ethereum-optimism/op-geth) / [op-node](https://github.com/ethereum-optimism/optimism/tree/develop/op-node)) enhanced with [AggKit](https://github.com/agglayer/aggkit) for seamless Agglayer connectivity

### Use Cases

- Teams looking to deploy Kurtosis CDK to an external L1 like Sepolia.

### Deployment

Kurtosis CDK is designed to be modular - so only minimal changes are required to attach to an existing L1. First create a `.yml` file to use for the deployment:

Then create a `.yml` file to use as the `--args-file` input.
```yaml title="deploy-to-external-l1.yml"
args:
  verbosity: debug

  ## L1 chain ID.
  l1_chain_id: 11155111
  # This mnemonic will be used to fund essential addresses on L1. It needs to have sufficient funds on the existing L1.
  l1_preallocated_mnemonic: "giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
  # The amount of ETH sent to the admin, sequence, aggregator, sequencer and other chosen addresses.
  l1_funding_amount: 1ether
  # The L1 HTTP RPC endpoint.
  l1_rpc_url: "http://el-1-geth-lighthouse:8545"
  # The L1 WS RPC endpoint.
  l1_ws_url: "ws://el-1-geth-lighthouse:8546"
```

Then continue with the deployment.
```bash
kurtosis run --args-file=./deploy-to-external-l1.yml .
```