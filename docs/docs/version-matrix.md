---
sidebar_position: 3
---

# Version Matrix

> This document is automatically generated.

## Contents

- [Test Environments](#test-environments)
- [Default Images](#default-images)
- [Kurtosis Packages](#kurtosis-packages)
- [Hard Forks](#hard-forks)

## Test Environments

This section lists all test environments with their configurations and component versions, organized by execution client.

### CDK OP Reth

- [cdk-opreth-sovereign-ecdsa-multisig](#cdk-opreth-sovereign-ecdsa-multisig)
- [cdk-opreth-sovereign-pessimistic](#cdk-opreth-sovereign-pessimistic)
- [cdk-opreth-zkrollup](#cdk-opreth-zkrollup)

### CDK Erigon

- [cdk-erigon-sovereign-ecdsa-multisig](#cdk-erigon-sovereign-ecdsa-multisig)
- [cdk-erigon-sovereign-pessimistic](#cdk-erigon-sovereign-pessimistic)
- [cdk-erigon-validium](#cdk-erigon-validium)
- [cdk-erigon-zkrollup](#cdk-erigon-zkrollup)

### CDK Besu

- [cdk-besu-sovereign-ecdsa-multisig](#cdk-besu-sovereign-ecdsa-multisig)

## CDK OP Reth

Environments using [op-reth](https://github.com/ethereum-optimism/optimism/tree/develop/rust/op-reth) as the L2 execution client.

### cdk-opreth-sovereign-ecdsa-multisig

- File path: `.github/tests/op-reth/sovereign-ecdsa-multisig.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | ✅ matches stable |
| agglayer | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | ✅ matches stable |
| agglayer-contracts | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | ✅ matches stable |
| op-batcher | [1.18.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.18.1) | [1.18.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.18.1) | ✅ matches stable |
| op-deployer | [0.9.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.9.0) | [0.9.0-allowlist](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.9.0-allowlist) | ⚡️ newer than stable |
| op-node | [1.20.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.20.1) | [1.20.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.20.1) | ✅ matches stable |
| op-proposer | [1.17.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-proposer/v1.17.0) | [1.17.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-proposer/v1.17.0) | ✅ matches stable |
| op-reth | [2.8.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-reth/v2.8.1) | [2.8.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-reth/v2.8.1) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC5](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC5) | [0.6.3](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.3) | ⚡️ newer than stable |

### cdk-opreth-sovereign-pessimistic

- File path: `.github/tests/op-reth/sovereign-pessimistic.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.5.4](https://github.com/agglayer/aggkit/releases/tag/v0.5.4) | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | 📌 pinned — Only supports aggkit 0.5.x so far. |
| agglayer | [0.6.0](https://github.com/agglayer/agglayer/releases/tag/v0.6.0) | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | 📌 pinned — aggkit 0.5.4 signs V2/V3 certs, rejected by agglayer 0.6.1+. |
| agglayer-contracts | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | ✅ matches stable |
| op-batcher | [1.18.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.18.1) | [1.18.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.18.1) | ✅ matches stable |
| op-deployer | [0.9.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.9.0) | [0.9.0-allowlist](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.9.0-allowlist) | ⚡️ newer than stable |
| op-node | [1.20.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.20.1) | [1.20.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.20.1) | ✅ matches stable |
| op-proposer | [1.17.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-proposer/v1.17.0) | [1.17.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-proposer/v1.17.0) | ✅ matches stable |
| op-reth | [2.8.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-reth/v2.8.1) | [2.8.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-reth/v2.8.1) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC5](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC5) | [0.6.3](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.3) | ⚡️ newer than stable |

### cdk-opreth-zkrollup

- File path: `.github/tests/op-succinct/mock-prover.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | ✅ matches stable |
| aggkit-prover | [2.2.1](https://github.com/agglayer/provers/releases/tag/v2.2.1) | [2.2.1](https://github.com/agglayer/provers/releases/tag/v2.2.1) | ✅ matches stable |
| agglayer | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | ✅ matches stable |
| agglayer-contracts | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | ✅ matches stable |
| op-batcher | [1.18.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.18.1) | [1.18.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.18.1) | ✅ matches stable |
| op-deployer | [0.9.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.9.0) | [0.9.0-allowlist](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.9.0-allowlist) | ⚡️ newer than stable |
| op-node | [1.19.5](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.19.5) | [1.20.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.20.1) | 📌 pinned — op-succinct 3.10.x cannot read op-node 1.19.6+ (dropped cross_unsafe_l2). |
| op-reth | [2.8.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-reth/v2.8.1) | [2.8.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-reth/v2.8.1) | ✅ matches stable |
| op-succinct-proposer | [3.10.0-agglayer](https://github.com/agglayer/op-succinct/releases/tag/v3.10.0-agglayer) | [3.13.0-agglayer](https://github.com/agglayer/op-succinct/releases/tag/v3.13.0-agglayer) | 📌 pinned — Only supports op-succinct 3.10.x so far. |
| zkevm-bridge-service | [0.6.4-RC5](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC5) | [0.6.3](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.3) | ⚡️ newer than stable |

## CDK Erigon

Environments using [cdk-erigon](https://github.com/0xPolygon/cdk-erigon) as the L2 execution client.

### cdk-erigon-sovereign-ecdsa-multisig

- File path: `.github/tests/cdk-erigon/sovereign-ecdsa-multisig.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | ✅ matches stable |
| agglayer | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | ✅ matches stable |
| agglayer-contracts | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | ✅ matches stable |
| cdk-erigon | [2.65.0-RC3](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.65.0-RC3) | [2.64.2](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.64.2) | ⚡️ newer than stable |
| zkevm-bridge-service | [0.6.4-RC5](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC5) | [0.6.3](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.3) | ⚡️ newer than stable |
| zkevm-pool-manager | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | ✅ matches stable |

### cdk-erigon-sovereign-pessimistic

- File path: `.github/tests/cdk-erigon/sovereign-pessimistic.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.5.4](https://github.com/agglayer/aggkit/releases/tag/v0.5.4) | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | 📌 pinned — Only supports aggkit 0.5.x so far. |
| agglayer | [0.6.0](https://github.com/agglayer/agglayer/releases/tag/v0.6.0) | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | 📌 pinned — aggkit 0.5.4 signs V2/V3 certs, rejected by agglayer 0.6.1+. |
| agglayer-contracts | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | ✅ matches stable |
| cdk-erigon | [2.65.0-RC3](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.65.0-RC3) | [2.64.2](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.64.2) | ⚡️ newer than stable |
| zkevm-bridge-service | [0.6.4-RC5](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC5) | [0.6.3](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.3) | ⚡️ newer than stable |
| zkevm-pool-manager | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | ✅ matches stable |

### cdk-erigon-validium

- File path: `.github/tests/cdk-erigon/validium.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| agglayer | [0.6.0-rc.5](https://github.com/agglayer/agglayer/releases/tag/v0.6.0-rc.5) | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | 📌 pinned — Only supports agglayer 0.6.0-rc.5 so far. |
| agglayer-contracts | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | ✅ matches stable |
| cdk-data-availability | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13) | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13) | ✅ matches stable |
| cdk-erigon | [2.61.24](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.24) | [2.64.2](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.64.2) | 📌 pinned — Only supports cdk-erigon 2.61.x so far. |
| cdk-node | [0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | [0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC5](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC5) | [0.6.3](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.3) | ⚡️ newer than stable |
| zkevm-pool-manager | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | ✅ matches stable |
| zkevm-prover | [8.0.0-RC16](https://github.com/0xPolygon/zkevm-prover/releases/tag/v8.0.0-RC16) | [7.0.4](https://github.com/0xPolygon/zkevm-prover/releases/tag/v7.0.4) | ⚡️ newer than stable |

### cdk-erigon-zkrollup

- File path: `.github/tests/cdk-erigon/rollup.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| agglayer | [0.6.0-rc.5](https://github.com/agglayer/agglayer/releases/tag/v0.6.0-rc.5) | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | 📌 pinned — Only supports agglayer 0.6.0-rc.5 so far. |
| agglayer-contracts | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | ✅ matches stable |
| cdk-erigon | [2.61.24](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.24) | [2.64.2](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.64.2) | 📌 pinned — Only supports cdk-erigon 2.61.x so far. |
| cdk-node | [0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | [0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC5](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC5) | [0.6.3](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.3) | ⚡️ newer than stable |
| zkevm-pool-manager | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | ✅ matches stable |
| zkevm-prover | [8.0.0-RC16](https://github.com/0xPolygon/zkevm-prover/releases/tag/v8.0.0-RC16) | [7.0.4](https://github.com/0xPolygon/zkevm-prover/releases/tag/v7.0.4) | ⚡️ newer than stable |

## CDK Besu

Environments using [Besu](https://github.com/hyperledger/besu) as the L2 execution client.

### cdk-besu-sovereign-ecdsa-multisig

- File path: `.github/tests/besu/sovereign-ecdsa-multisig.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | [0.11.1](https://github.com/agglayer/aggkit/releases/tag/v0.11.1) | ✅ matches stable |
| agglayer | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | [0.6.2](https://github.com/agglayer/agglayer/releases/tag/v0.6.2) | ✅ matches stable |
| agglayer-contracts | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | [12.2.3](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.3) | ✅ matches stable |
| besu | [26.11.0](https://github.com/hyperledger/besu/releases/tag/26.11.0) | [26.11.0](https://github.com/hyperledger/besu/releases/tag/26.11.0) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC5](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC5) | [0.6.3](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.3) | ⚡️ newer than stable |

## Default Images

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| anvil | [1.9.0](https://github.com/foundry-rs/foundry/releases/tag/v1.9.0) | [1.9.0](https://github.com/foundry-rs/foundry/releases/tag/v1.9.0) | ✅ matches stable |
| geth | [1.17.10](https://github.com/ethereum/go-ethereum/releases/tag/v1.17.10) | [1.17.10](https://github.com/ethereum/go-ethereum/releases/tag/v1.17.10) | ✅ matches stable |
| lighthouse | [8.3.2](https://github.com/sigp/lighthouse/releases/tag/v8.3.2) | [8.3.2](https://github.com/sigp/lighthouse/releases/tag/v8.3.2) | ✅ matches stable |
| reth | [2.10.0](https://github.com/paradigmxyz/reth/releases/tag/v2.10.0) | [2.10.0](https://github.com/paradigmxyz/reth/releases/tag/v2.10.0) | ✅ matches stable |
| status-checker | [0.2.10](https://github.com/0xPolygon/status-checker/releases/tag/v0.2.10) | [0.2.10](https://github.com/0xPolygon/status-checker/releases/tag/v0.2.10) | ✅ matches stable |

## Kurtosis Packages

External Kurtosis packages this package depends on. Versions are pinned in the [`replace` block of `kurtosis.yml`](https://github.com/0xPolygon/kurtosis-cdk/blob/main/kurtosis.yml), which is the single place to bump them.

| Package | Pinned Version | Latest Stable Version | Status |
|---------|----------------|-----------------------|--------|
| [github.com/agglayer/optimism-package](https://github.com/agglayer/optimism-package) | [v2.0.0](https://github.com/agglayer/optimism-package/releases/tag/v2.0.0) | [v2.0.0](https://github.com/agglayer/optimism-package/releases/tag/v2.0.0) | ✅ matches stable |
| [github.com/ethpandaops/ethereum-package](https://github.com/ethpandaops/ethereum-package) | [5795b77e6523](https://github.com/ethpandaops/ethereum-package/tree/5795b77e65235ad223d4d3b413b2739190bf60cc) | [HEAD (5795b77e6523)](https://github.com/ethpandaops/ethereum-package/tree/5795b77e65235ad223d4d3b413b2739190bf60cc) | ✅ matches stable |
| [github.com/kurtosis-tech/grafana-package](https://github.com/kurtosis-tech/grafana-package) | [c8ff0b52d25d](https://github.com/kurtosis-tech/grafana-package/tree/c8ff0b52d25deb0bc4ec95971dcf25b2fca11287) | [HEAD (c8ff0b52d25d)](https://github.com/kurtosis-tech/grafana-package/tree/c8ff0b52d25deb0bc4ec95971dcf25b2fca11287) | ✅ matches stable |
| [github.com/kurtosis-tech/prometheus-package](https://github.com/kurtosis-tech/prometheus-package) | [f3402ebad8cf](https://github.com/kurtosis-tech/prometheus-package/tree/f3402ebad8cffe98eef990e41ca863f7e8746c21) | [HEAD (f3402ebad8cf)](https://github.com/kurtosis-tech/prometheus-package/tree/f3402ebad8cffe98eef990e41ca863f7e8746c21) | ✅ matches stable |
| [github.com/xavier-romero/kurtosis-blockscout](https://github.com/xavier-romero/kurtosis-blockscout) | [9de7765a6c98](https://github.com/xavier-romero/kurtosis-blockscout/tree/9de7765a6c98c8c357f747ff953fdbc0e39ebc3d) | [HEAD (9de7765a6c98)](https://github.com/xavier-romero/kurtosis-blockscout/tree/9de7765a6c98c8c357f747ff953fdbc0e39ebc3d) | ✅ matches stable |

## Hard Forks

Fork schedule of the devnet, checked against the source of the clients and packages at the versions pinned above. It only changes when a pin or the package config does, so a fork that is merely announced upstream never shows up as drift. These rows are informational and never bumped automatically.

| Devnet status | Meaning |
|--------|---------|
| ✅ enabled | Activated by the devnet and known to the pinned clients. |
| 💤 not enabled | Known to the pinned clients, but the devnet leaves it off. |
| ⏳ not supported yet | Exposed by the package, but not known to a pinned client yet. |
| ❌ enabled but unsupported | Configured by the devnet, but a pinned client does not know it and ignores the setting. |
| ⚙️ op-deployer default | Left unset by the devnet, so op-deployer's standard schedule decides when it activates. |

### L1

Fork epochs are the ethereum-package `minimal` preset defaults, overridden in [`src/l1/ethereum.star`](https://github.com/0xPolygon/kurtosis-cdk/blob/main/src/l1/ethereum.star). Checked against [ethereum-package 5795b77e6523](https://github.com/ethpandaops/ethereum-package/blob/5795b77e65235ad223d4d3b413b2739190bf60cc/src/package_io/input_parser.star), [geth v1.17.10](https://github.com/ethereum/go-ethereum/blob/v1.17.10/params/config.go) and [lighthouse v8.3.2](https://github.com/sigp/lighthouse/blob/v8.3.2/common/eth2_network_config/built_in_network_configs/mainnet/config.yaml).

| CL fork | EL fork | Devnet epoch | Sepolia epoch | Mainnet epoch | Supported by geth | Supported by lighthouse | Devnet status |
|------|---------|--------------|---------------|---------------|------|------------|--------|
| altair | — | 0 | [50](https://beaconscan.com/sepolia/epoch/50) | [74240](https://beaconscan.com/epoch/74240) | — | yes | ✅ enabled |
| bellatrix | — | 0 | [100](https://beaconscan.com/sepolia/epoch/100) | [144896](https://beaconscan.com/epoch/144896) | — | yes | ✅ enabled |
| capella | shanghai | 0 | [56832](https://beaconscan.com/sepolia/epoch/56832) | [194048](https://beaconscan.com/epoch/194048) | yes | yes | ✅ enabled |
| deneb | cancun | 0 | [132608](https://beaconscan.com/sepolia/epoch/132608) | [269568](https://beaconscan.com/epoch/269568) | yes | yes | ✅ enabled |
| electra | prague | 0 | [222464](https://beaconscan.com/sepolia/epoch/222464) | [364032](https://beaconscan.com/epoch/364032) | yes | yes | ✅ enabled |
| fulu | osaka | 0 | [272640](https://beaconscan.com/sepolia/epoch/272640) | [411392](https://beaconscan.com/epoch/411392) | yes | yes | ✅ enabled |
| gloas | amsterdam | 0 | [353024](https://beaconscan.com/sepolia/epoch/353024) | unscheduled | yes | yes | ✅ enabled |
| bpo_1 | bpo1 | 0 | [274176](https://beaconscan.com/sepolia/epoch/274176) | [412672](https://beaconscan.com/epoch/412672) | yes | yes | ✅ enabled |
| bpo_2 | bpo2 | 0 | [275712](https://beaconscan.com/sepolia/epoch/275712) | [419072](https://beaconscan.com/epoch/419072) | yes | yes | ✅ enabled |

Not scheduled on mainnet yet: `heze` (💤 not enabled), `bpo_3` (💤 not enabled), `bpo_4` (💤 not enabled), `bpo_5` (💤 not enabled).

### OP Stack

Fork times are offsets in seconds from the L2 genesis: the optimism-package defaults, overridden in [`src/package_io/op_input_parser.star`](https://github.com/0xPolygon/kurtosis-cdk/blob/main/src/package_io/op_input_parser.star). Forks before Fjord always activate at genesis. Checked against [optimism-package v2.0.0](https://github.com/agglayer/optimism-package/blob/v2.0.0/src/l2/input_parser.star) and [op-node v1.20.1](https://github.com/ethereum-optimism/optimism/blob/op-node/v1.20.1/op-core/forks/forks.go).

| Fork | Devnet offset (s) | Supported by op-node | Devnet status |
|------|-------------------|---------|--------|
| fjord | 0 | yes | ✅ enabled |
| granite | 0 | yes | ✅ enabled |
| holocene | — | yes | ⚙️ op-deployer default |
| isthmus | 0 | yes | ✅ enabled |
| jovian | — | yes | ⚙️ op-deployer default |
| karst | — | yes | ⚙️ op-deployer default — no knob in optimism-package |
| lagoon | — | yes | ⚙️ op-deployer default — no knob in optimism-package |
| interop | — | no | ⏳ not supported yet |
