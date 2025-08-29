# Test Configurations

This document outlines the various Polygon CDK configurations tested in our CI pipeline. Each configuration represents a different combination of chain type, consensus mechanism, proof system, and execution client, covering the spectrum from traditional zkEVM rollups and validiums to aggchain with pessimistic and full execution proofs.

| Chain | verifierType | SC consensus | Proofs/Prover | Client | Test Configuration |
|-------|--------------|--------------|---------------|--------|--------------------|
| zkEVM | StateTransition | PolygonZkEVMEtrog | FEP # Hermez | cdk-erigon | [cdk-erigon/rollup.yml](cdk-erigon/rollup.yml) (fork12) |
| Valididum | StateTransition | PolygonValidiumEtrog | FEP # Hermez | cdk-erigon | [cdk-erigon/validium.yml](cdk-erigon/validium.yml) (fork12) |
| v0.2.0-ECDSA | Pessimistic | PolygonPessimisticConsensus | PP # SP1 | cdk-erigon OR op-stack | - [cdk-erigon/sovereign.yml](cdk-erigon/sovereign.yml) (fork12)<br>- [op-geth/sovereign.yml](op-geth/sovereign.yml) - **default environment** |
| v0.3.0-ECDSA | ALGateway | AggchainECDSA | PP # SP1 | not supported (aggkit not built) | [op-geth/ecdsa.yml](op-geth/ecdsa.yml.norun) |
| v0.3.0-FEP | ALGateway | AggchainFEP | (PP + FEP) # SP1 | op-stack | - [op-succinct/mock-prover.yml](op-succinct/mock-prover.yml)<br>- [op-succinct/real-prover.yml](op-succinct/real-prover.yml)|

For reference: <https://agglayer.github.io/protocol-team-docs/aggregation-layer/v0.3.0/SC-specs/#16-table-agglayer-chains-supported>

## Nightly

In addition to the standard environments, we also test a few additional environments in the nightly workflow:

| Chain | verifierType | SC consensus | Proofs/Prover | Client | Fork ID | Test Configuration |
|-------|--------------|--------------|---------------|--------|---------|--------------------|
| zkEVM | StateTransition | PolygonZkEVMEtrog | FEP # Hermez | cdk-erigon | 9 | [fork9-cdk-erigon-rollup.yml](nightly/cdk-erigon/fork9-cdk-erigon-rollup.yml) |
| Valididum | StateTransition | PolygonValidiumEtrog | FEP # Hermez | cdk-erigon | 9 | [fork9-cdk-erigon-validium.yml](nightly/cdk-erigon/fork9-cdk-erigon-validium.yml) |
| zkEVM | StateTransition | PolygonZkEVMEtrog | FEP # Hermez | cdk-erigon | 11 | [fork11-cdk-erigon-rollup.yml](nightly/cdk-erigon/fork11-cdk-erigon-rollup.yml) |
| Valididum | StateTransition | PolygonValidiumEtrog | FEP # Hermez | cdk-erigon | 11 | [fork11-cdk-erigon-validium.yml](nightly/cdk-erigon/fork11-cdk-erigon-validium.yml) |
| zkEVM | StateTransition | PolygonZkEVMEtrog | FEP # Hermez | cdk-erigon | 13 | [fork13-cdk-erigon-rollup.yml](nightly/cdk-erigon/fork13-cdk-erigon-rollup.yml) |
| Valididum | StateTransition | PolygonValidiumEtrog | FEP # Hermez | cdk-erigon | 13 | [fork13-cdk-erigon-validium.yml](nightly/cdk-erigon/fork13-cdk-erigon-validium.yml) |
