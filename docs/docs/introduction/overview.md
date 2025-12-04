---
slug: /
sidebar_position: 1
---

# Overview

👋 Welcome to the Polygon CDK Kurtosis package documentation!

This project provides a modular, reproducible environment for developing, testing, and running [Polygon CDK](https://docs.agglayer.dev/cdk/) devnets using [Kurtosis](https://kurtosis.com/).

Specifically, this package will:

1. Spin up a local L1 blockchain, fully customizable with multi-client support, leveraging the [Ethereum Kurtosis package](https://github.com/ethpandaops/ethereum-package).
2. Deploy [Agglayer contracts](https://github.com/agglayer/agglayer-contracts) on the L1 chain.
3. Start the [Agglayer](https://github.com/agglayer/agglayer) and its (mock) [prover](https://github.com/agglayer/provers), enabling trustless cross-chain token transfers and message-passing, as well as more complex operations between L2 chains, secured by zk proofs.
4. Launch a local L2 blockchain, fully customizable with multi-client support, leveraging the [Optimism Kurtosis package](https://github.com/ethpandaops/optimism-package). It will deploy an Optimism stack enhanced with [AggKit](https://github.com/agglayer/aggkit) for seamless Agglayer connectivity.
5. Deploy the [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.

Optional features:

- Run transaction and bridge spammers to simulate network load.
- Deploy monitoring solutions such as [Prometheus](https://prometheus.io/), [Grafana](https://grafana.com/), [Panoptichain](https://github.com/0xPolygon/panoptichain) and [Blockscout](https://www.blockscout.com/) to observe the network.

:::info
This package is for development and testing only — **not for production use!**
:::

## Sections

### [Getting Started](./getting-started.md)

Install Kurtosis and set up your first devnet.

### [Configuration](../configuration/overview.md)

Learn how to configure your devnet deployment.

### [Version Matrix](../version-matrix.md)

A list of all test environments with their configurations and component versions.

### [Advanced](../advanced/overview.md)

Advanced guides and resources for performing complex operations within a devnet.

### [Contributing](../contributing.md)

Help us improve the package.

### Appendix

References, troubleshooting, and more.

- [FAQ](../appendix/faq.md)
