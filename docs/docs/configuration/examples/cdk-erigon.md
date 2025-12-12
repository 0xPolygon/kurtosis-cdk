---
sidebar_position: 2
---

# CDK Erigon

These configurations are based on [cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon) and fork 12 of the [agglayer contracts](https://github.com/agglayer/agglayer-contracts).

## ZK Rollup

This configuration deploys a ZK rollup environment powered by Polygon's [zkEVM Prover](https://github.com/0xPolygonHermez/zkevm-prover). It ensures data availability on-chain, providing high security and Ethereum-level guarantees.

#### What gets deployed?

- L1 Ethereum blockchain (lighthouse/geth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer) and [mock prover](https://github.com/agglayer/provers)).
- L2 CDK-Erigon blockchain ([cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon), [zkevm-pool-manager](https://github.com/0xPolygon/zkevm-pool-manager), [zkevm-prover](https://github.com/0xPolygonHermez/zkevm-prover)and executor, [cdk-node](https://github.com/0xPolygon/cdk)).
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.

#### Best for

- Applications requiring Ethereum-level security guarantees.
- Scenarios where on-chain data availability is critical.

#### Deployment

To deploy this environment:

```bash
kurtosis run --enclave cdk --args-file .github/tests/cdk-erigon/rollup.yml .
```

## ZK Validium

This configuration deploys a ZK validium environment, which stores data off-chain for reduced costs while maintaining security through zk proofs.

#### What gets deployed?

- L1 Ethereum blockchain (lighthouse/geth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer) and [mock prover](https://github.com/agglayer/provers)).
- L2 Optimism blockchain ([cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon), [zkevm-pool-manager](https://github.com/0xPolygon/zkevm-pool-manager), [zkevm-prover](https://github.com/0xPolygonHermez/zkevm-prover)and executor, [cdk-node](https://github.com/0xPolygon/cdk)).
- Data availability layer, leveraging the [cdk-dac](https://github.com/0xPolygon/cdk-data-availability).
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.
- Additional services: bridge spammer to generate load on the network.

#### Best for

- Applications requiring lower transaction costs.
- Scenarios where off-chain data availability is acceptable.

#### Deployment

To deploy this environment:

```bash
kurtosis run --enclave cdk --args-file .github/tests/cdk-erigon/validium.yml .
```

## Sovereign

This configuration deploys a sovereign chain that operates independently of L1 while maintaining zk proof capabilities.

#### What gets deployed?

- L1 Ethereum blockchain (lighthouse/geth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer) and [mock prover](https://github.com/agglayer/provers)).
- L2 Optimism blockchain ([cdk-erigon](https://github.com/0xPolygonHermez/cdk-erigon), [zkevm-pool-manager](https://github.com/0xPolygon/zkevm-pool-manager) and [cdk-node](https://github.com/0xPolygon/cdk)).
- Data availability layer, leveraging the [cdk-dac](https://github.com/0xPolygon/cdk-data-availability).
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.

#### Best for

- Independent chains that do not rely on L1 for security.
- Testing sovereign chain concepts.

#### Deployment

To deploy this environment:

```bash
kurtosis run --enclave cdk --args-file .github/tests/cdk-erigon/sovereign-ecdsa-multisig.yml .
```

The former sovereign environment based on the `pessimistic` consensus contract type can be deployed with:

```bash
kurtosis run --enclave cdk --args-file .github/tests/cdk-erigon/sovereign-pessimistic.yml .
```
