---
sidebar_position: 3
---

# Version Matrix

> This document is automatically generated.

## Test Environments

This section lists all test environments with their configurations and component versions, organized by execution client.

### CDK OP Geth

- [cdk-opgeth-sovereign-ecdsa-multisig](#cdk-opgeth-sovereign-ecdsa-multisig)
- [cdk-opgeth-sovereign-pessimistic](#cdk-opgeth-sovereign-pessimistic)
- [cdk-opgeth-zkrollup](#cdk-opgeth-zkrollup)

### CDK Erigon

- [cdk-erigon-sovereign-ecdsa-multisig](#cdk-erigon-sovereign-ecdsa-multisig)
- [cdk-erigon-sovereign-pessimistic](#cdk-erigon-sovereign-pessimistic)
- [cdk-erigon-validium](#cdk-erigon-validium)
- [cdk-erigon-zkrollup](#cdk-erigon-zkrollup)

## CDK OP Geth

Environments using [op-geth](https://github.com/ethereum-optimism/optimism) as the L2 execution client.

### cdk-opgeth-sovereign-ecdsa-multisig

- File path: `.github/tests/op-geth/sovereign-ecdsa-multisig.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.8.0-beta3](https://github.com/agglayer/aggkit/releases/tag/v0.8.0-beta3) | [0.7.2](https://github.com/agglayer/aggkit/releases/tag/v0.7.2) | ⚡️ newer than stable |
| aggkit-prover | [1.9.0](https://github.com/agglayer/provers/releases/tag/v1.9.0) | [1.8.0](https://github.com/agglayer/provers/releases/tag/v1.8.0) | ⚡️ newer than stable |
| agglayer | [0.4.4-remove-agglayer-prover](https://github.com/agglayer/agglayer/tree/38ffe04e71bb6b0eb22a244dbd40d189e1b0d78f) | [0.4.4](https://github.com/agglayer/agglayer/releases/tag/v0.4.4) | ⚡️ newer than stable |
| agglayer-contracts | [12.2.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.0) | [11.0.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0) | ⚡️ newer than stable |
| op-batcher | [1.16.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.16.2) | [1.16.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.16.2) | ✅ matches stable |
| op-deployer | [0.5.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.5.1) | [0.5.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.5.2) | 🚨 behind stable |
| op-geth | [1.101603.5](https://github.com/ethereum-optimism/op-geth/releases/tag/v1.101603.5) | [1.101603.5](https://github.com/ethereum-optimism/op-geth/releases/tag/v1.101603.5) | ✅ matches stable |
| op-node | [1.16.3](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.16.3) | [1.16.3](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.16.3) | ✅ matches stable |
| op-proposer | [1.10.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-proposer/v1.10.0) | [1.10.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-proposer/v1.10.0) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | ✅ matches stable |

### cdk-opgeth-sovereign-pessimistic

- File path: `.github/tests/op-geth/sovereign-pessimistic.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.5.4](https://github.com/agglayer/aggkit/releases/tag/v0.5.4) | [0.7.2](https://github.com/agglayer/aggkit/releases/tag/v0.7.2) | 🚨 behind stable |
| aggkit-prover | [1.9.0](https://github.com/agglayer/provers/releases/tag/v1.9.0) | [1.8.0](https://github.com/agglayer/provers/releases/tag/v1.8.0) | ⚡️ newer than stable |
| agglayer | [0.4.4-remove-agglayer-prover](https://github.com/agglayer/agglayer/tree/38ffe04e71bb6b0eb22a244dbd40d189e1b0d78f) | [0.4.4](https://github.com/agglayer/agglayer/releases/tag/v0.4.4) | ⚡️ newer than stable |
| agglayer-contracts | [12.2.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.0) | [11.0.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0) | ⚡️ newer than stable |
| op-batcher | [1.16.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.16.2) | [1.16.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.16.2) | ✅ matches stable |
| op-deployer | [0.5.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.5.1) | [0.5.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.5.2) | 🚨 behind stable |
| op-geth | [1.101603.5](https://github.com/ethereum-optimism/op-geth/releases/tag/v1.101603.5) | [1.101603.5](https://github.com/ethereum-optimism/op-geth/releases/tag/v1.101603.5) | ✅ matches stable |
| op-node | [1.16.3](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.16.3) | [1.16.3](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.16.3) | ✅ matches stable |
| op-proposer | [1.10.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-proposer/v1.10.0) | [1.10.0](https://github.com/ethereum-optimism/optimism/releases/tag/op-proposer/v1.10.0) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | ✅ matches stable |

### cdk-opgeth-zkrollup

- File path: `.github/tests/op-succinct/mock-prover.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.8.0-beta3](https://github.com/agglayer/aggkit/releases/tag/v0.8.0-beta3) | [0.7.2](https://github.com/agglayer/aggkit/releases/tag/v0.7.2) | ⚡️ newer than stable |
| aggkit-prover | [1.9.0](https://github.com/agglayer/provers/releases/tag/v1.9.0) | [1.8.0](https://github.com/agglayer/provers/releases/tag/v1.8.0) | ⚡️ newer than stable |
| agglayer | [0.4.4-remove-agglayer-prover](https://github.com/agglayer/agglayer/tree/38ffe04e71bb6b0eb22a244dbd40d189e1b0d78f) | [0.4.4](https://github.com/agglayer/agglayer/releases/tag/v0.4.4) | ⚡️ newer than stable |
| agglayer-contracts | [12.2.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.0) | [11.0.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0) | ⚡️ newer than stable |
| op-batcher | [1.16.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.16.2) | [1.16.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-batcher/v1.16.2) | ✅ matches stable |
| op-deployer | [0.5.1](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.5.1) | [0.5.2](https://github.com/ethereum-optimism/optimism/releases/tag/op-deployer/v0.5.2) | 🚨 behind stable |
| op-geth | [1.101603.5](https://github.com/ethereum-optimism/op-geth/releases/tag/v1.101603.5) | [1.101603.5](https://github.com/ethereum-optimism/op-geth/releases/tag/v1.101603.5) | ✅ matches stable |
| op-node | [1.16.3](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.16.3) | [1.16.3](https://github.com/ethereum-optimism/optimism/releases/tag/op-node/v1.16.3) | ✅ matches stable |
| op-succinct-proposer | [3.4.0-rc.1-agglayer](https://github.com/agglayer/op-succinct/releases/tag/v3.4.0-rc.1-agglayer) | [3.4.0-rc.1](https://github.com/agglayer/op-succinct/releases/tag/v3.4.0-rc.1) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | ✅ matches stable |

## CDK Erigon

Environments using [cdk-erigon](https://github.com/0xPolygon/cdk-erigon) as the L2 execution client.

### cdk-erigon-sovereign-ecdsa-multisig

- File path: `.github/tests/cdk-erigon/sovereign-ecdsa-multisig.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.8.0-beta3](https://github.com/agglayer/aggkit/releases/tag/v0.8.0-beta3) | [0.7.2](https://github.com/agglayer/aggkit/releases/tag/v0.7.2) | ⚡️ newer than stable |
| aggkit-prover | [1.9.0](https://github.com/agglayer/provers/releases/tag/v1.9.0) | [1.8.0](https://github.com/agglayer/provers/releases/tag/v1.8.0) | ⚡️ newer than stable |
| agglayer | [0.4.4-remove-agglayer-prover](https://github.com/agglayer/agglayer/tree/38ffe04e71bb6b0eb22a244dbd40d189e1b0d78f) | [0.4.4](https://github.com/agglayer/agglayer/releases/tag/v0.4.4) | ⚡️ newer than stable |
| agglayer-contracts | [12.2.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.0) | [11.0.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0) | ⚡️ newer than stable |
| cdk-erigon | [2.65.0-RC1](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.65.0-RC1) | [2.61.24](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.24) | ⚡️ newer than stable |
| zkevm-bridge-service | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | ✅ matches stable |
| zkevm-pool-manager | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | ✅ matches stable |

### cdk-erigon-sovereign-pessimistic

- File path: `.github/tests/cdk-erigon/sovereign-pessimistic.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit | [0.5.4](https://github.com/agglayer/aggkit/releases/tag/v0.5.4) | [0.7.2](https://github.com/agglayer/aggkit/releases/tag/v0.7.2) | 🚨 behind stable |
| aggkit-prover | [1.9.0](https://github.com/agglayer/provers/releases/tag/v1.9.0) | [1.8.0](https://github.com/agglayer/provers/releases/tag/v1.8.0) | ⚡️ newer than stable |
| agglayer | [0.4.4-remove-agglayer-prover](https://github.com/agglayer/agglayer/tree/38ffe04e71bb6b0eb22a244dbd40d189e1b0d78f) | [0.4.4](https://github.com/agglayer/agglayer/releases/tag/v0.4.4) | ⚡️ newer than stable |
| agglayer-contracts | [12.2.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.0) | [11.0.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0) | ⚡️ newer than stable |
| cdk-erigon | [2.65.0-RC1](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.65.0-RC1) | [2.61.24](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.24) | ⚡️ newer than stable |
| zkevm-bridge-service | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | ✅ matches stable |
| zkevm-pool-manager | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | ✅ matches stable |

### cdk-erigon-validium

- File path: `.github/tests/cdk-erigon/validium.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit-prover | [1.9.0](https://github.com/agglayer/provers/releases/tag/v1.9.0) | [1.8.0](https://github.com/agglayer/provers/releases/tag/v1.8.0) | ⚡️ newer than stable |
| agglayer | [0.4.4-remove-agglayer-prover](https://github.com/agglayer/agglayer/tree/38ffe04e71bb6b0eb22a244dbd40d189e1b0d78f) | [0.4.4](https://github.com/agglayer/agglayer/releases/tag/v0.4.4) | ⚡️ newer than stable |
| agglayer-contracts | [12.2.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.0) | [11.0.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0) | ⚡️ newer than stable |
| cdk-erigon | [2.61.24](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.24) | [2.61.24](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.24) | ✅ matches stable |
| cdk-node | [0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | [0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | ✅ matches stable |
| zkevm-da | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13) | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13) | ✅ matches stable |
| zkevm-pool-manager | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | ✅ matches stable |
| zkevm-prover | [8.0.0-RC16](https://github.com/0xPolygon/zkevm-prover/releases/tag/v8.0.0-RC16) | [8.0.0-RC16](https://github.com/0xPolygon/zkevm-prover/releases/tag/v8.0.0-RC16) | ✅ matches stable |

### cdk-erigon-zkrollup

- File path: `.github/tests/cdk-erigon/rollup.yml`

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| aggkit-prover | [1.9.0](https://github.com/agglayer/provers/releases/tag/v1.9.0) | [1.8.0](https://github.com/agglayer/provers/releases/tag/v1.8.0) | ⚡️ newer than stable |
| agglayer | [0.4.4-remove-agglayer-prover](https://github.com/agglayer/agglayer/tree/38ffe04e71bb6b0eb22a244dbd40d189e1b0d78f) | [0.4.4](https://github.com/agglayer/agglayer/releases/tag/v0.4.4) | ⚡️ newer than stable |
| agglayer-contracts | [12.2.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v12.2.0) | [11.0.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0) | ⚡️ newer than stable |
| cdk-erigon | [2.61.24](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.24) | [2.61.24](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.24) | ✅ matches stable |
| cdk-node | [0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | [0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | ✅ matches stable |
| zkevm-bridge-service | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | [0.6.4-RC1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.4-RC1) | ✅ matches stable |
| zkevm-pool-manager | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | [0.1.3](https://github.com/0xPolygon/zkevm-pool-manager/releases/tag/v0.1.3) | ✅ matches stable |
| zkevm-prover | [8.0.0-RC16](https://github.com/0xPolygon/zkevm-prover/releases/tag/v8.0.0-RC16) | [8.0.0-RC16](https://github.com/0xPolygon/zkevm-prover/releases/tag/v8.0.0-RC16) | ✅ matches stable |

## Default Images

| Component | Version Deployed in Kurtosis	 | Latest Stable Version | Status |
|-----------|-------------------------------|-----------------------|--------|
| geth | [1.16.7](https://github.com/ethereum/go-ethereum/releases/tag/v1.16.7) | [1.16.7](https://github.com/ethereum/go-ethereum/releases/tag/v1.16.7) | ✅ matches stable |
| lighthouse | [8.0.1](https://github.com/sigp/lighthouse/releases/tag/v8.0.1) | [8.0.1](https://github.com/sigp/lighthouse/releases/tag/v8.0.1) | ✅ matches stable |
