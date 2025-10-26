---
sidebar_position: 1
---

# CDK OP Geth

These configurations are based on the OP stack and more specifically on [op-geth](https://github.com/ethereum-optimism/op-geth).

## Sovereign

This is the default configuration for Polygon CDK. It deploys a minimal but fully functional rollup environment based on the Optimism stack, ideal for getting started quickly and testing basic functionality.

#### What gets deployed?

- L1 Ethereum blockchain (lighthouse/geth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer) and [mock prover](https://github.com/agglayer/provers)).
- L2 Optimism blockchain (op-geth/op-node) enhanced with [AggKit](https://github.com/agglayer/aggkit) for seamless Agglayer connectivity.
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.

#### Best For

- Developers getting started with Polygon CDK.
- Testing basic rollup functionality.
- Lightweight environments with minimal resource requirements.

#### Deployment

To deploy this environment:

```bash
kurtosis run --enclave cdk .
```

## ZK Rollup

These configurations enhance the standard [CDK OP Geth Sovereign](#sovereign) environment with zero-knowledge proofs for block execution verification, powered by [OP Succinct](https://succinctlabs.github.io/op-succinct/).

- [Mock Prover](#mock-prover)
- [Real Prover](#real-prover)

:::info
The key difference is that the mock prover simulates proof generation, while the real prover uses the [Succinct Prover Network](https://docs.succinct.xyz/docs/protocol/introduction) for actual zero-knowledge proofs.
:::

### Mock Prover

This setup is perfect for testing as it simulates the OP Succinct proving system without the computational overhead of generating real zero-knowledge proofs.

#### What gets deployed?

- L1 Ethereum blockchain (lighthouse/geth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer service](https://github.com/agglayer/agglayer) and [mock prover](https://github.com/agglayer/provers)).
- [Succinct's SP1 contracts](https://github.com/succinctlabs/sp1-contracts) for onchain verification of SP1 EVM proofs.
- L2 Optimism blockchain (op-geth/op-node) enhanced with [AggKit](https://github.com/agglayer/aggkit) and its prover for seamless Agglayer connectivity as well as [OP Succinct's proposer](https://github.com/succinctlabs/op-succinct), instead of the regular OP proposer.
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.
- Additional services: bridge spammer to generate load on the network.

#### Best For

- Testing environments where computational efficiency is a priority.
- Scenarios that do not require real zero-knowledge proofs.

#### Deployment

To deploy this environment:

```bash
kurtosis run --enclave cdk --args-file .github/tests/chains/op-succinct.yml .
```

### Real Prover

This configuration deploys a production-like environment with actual zero-knowledge proof generation..

#### What gets deployed?

- L1 Ethereum blockchain (lighthouse/geth).
- Agglayer stack ([contracts](https://github.com/agglayer/agglayer-contracts), [agglayer](https://github.com/agglayer/agglayer) service and [SP1 prover](https://docs.succinct.xyz/docs/protocol/introduction) - the prover is not deployed locally, instead we leverage the [Succinct Prover Network](https://docs.succinct.xyz/docs/network/introduction)).
- [Succinct's SP1 contracts](https://github.com/succinctlabs/sp1-contracts) for onchain verification of SP1 EVM proofs.
- L2 Optimism blockchain (op-geth/op-node) enhanced with [AggKit](https://github.com/agglayer/aggkit) and its prover for seamless Agglayer connectivity as well as [OP Succinct's proposer](https://github.com/succinctlabs/op-succinct), instead of the regular OP proposer.
- [zkEVM bridge](https://github.com/0xPolygonHermez/zkevm-bridge-service) to facilitate asset bridging between L1 and L2 chains.
- Additional services: bridge spammer to generate load on the network.

#### Best For

- Production-like environments requiring real zero-knowledge proofs.
- Scenarios where cryptographic security guarantees are essential.

#### Deployment

To deploy this environment:

```bash
kurtosis run --enclave cdk --args-file .github/tests/chains/op-succinct-real-prover.yml .
```
