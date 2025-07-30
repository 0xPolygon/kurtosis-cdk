# Polygon CDK Version Matrix

*Last updated: 2025-07-30T10:46:41.016342*
*Total components tracked: 17*
*Total test scenarios: 35*

---

**Note**: This version matrix is automatically generated. 
For the most up-to-date information, check the individual component repositories.

## Fork Compatibility Matrix

Which versions of the CDK stack are meant to work together?

| Fork ID | Consensus | CDK Erigon | ZkEVM Prover | Agglayer Contracts | Data Availability | Bridge Service |
| --- | --- | --- | --- | --- | --- | --- |
| 9 | validium | [v2.61.19](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v2.61.19)✅ | [v6.0.8](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v6.0.8)✅ | [v6.0.0-rc.1-fork.9](https://github.com/agglayer/agglayer-contracts/releases/tag/v6.0.0-rc.1-fork.9)🧪 | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13)✅ | [v0.6.2-RC2](https://github.com/0xPolygonHermez/zkevm-bridge-service/releases/tag/v0.6.2-RC2)🧪 |
| 11 | validium | [v2.61.19](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v2.61.19)✅ | [v7.0.4-hotfix.2-fork.11](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v7.0.4-hotfix.2)📌 | [v7.0.0-rc.2-fork.11](https://github.com/agglayer/agglayer-contracts/releases/tag/v7.0.0-rc.2-fork.11)🧪 | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13)✅ | [v0.6.2-RC2](https://github.com/0xPolygonHermez/zkevm-bridge-service/releases/tag/v0.6.2-RC2)🧪 |
| 12 | sovereign | [v2.61.19](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v2.61.19)✅ | [v8.0.0-RC16-fork.12](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v8.0.0-RC16)🧪 | [v11.0.0-rc.2-fork.12](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0-rc.2-fork.12)🧪 | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13)✅ | [v0.6.2-RC2](https://github.com/0xPolygonHermez/zkevm-bridge-service/releases/tag/v0.6.2-RC2)🧪 |
| 12 | validium | [v2.61.19](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v2.61.19)✅ | [v8.0.0-RC16-fork.12](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v8.0.0-RC16)🧪 | [v11.0.0-rc.2-fork.12](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0-rc.2-fork.12)🧪 | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13)✅ | [v0.6.2-RC2](https://github.com/0xPolygonHermez/zkevm-bridge-service/releases/tag/v0.6.2-RC2)🧪 |
| 13 | validium | [v2.61.19](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v2.61.19)✅ | [v9.0.0-RC3-fork.13](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v9.0.0-RC3)🧪 | [v8.1.0-rc.2-fork.13](https://github.com/agglayer/agglayer-contracts/releases/tag/v8.1.0-rc.2-fork.13)🧪 | [0.0.13](https://github.com/0xPolygon/cdk-data-availability/releases/tag/v0.0.13)✅ | [v0.6.2-RC2](https://github.com/0xPolygonHermez/zkevm-bridge-service/releases/tag/v0.6.2-RC2)🧪 |

## Test Scenarios

The following test scenarios are currently supported:

### Other

| Scenario | Description | Consensus | Fork ID | Key Components |
|----------|-------------|-----------|---------|----------------|
| additional-services | Standard Test Configuration | unknown | N/A |  |
| aggchain-ecdsa | Aggchain ECDSA | ecdsa | 0 |  |
| anvil-rollup | CDK (Rollup) | rollup | N/A |  |
| cardona-sepolia-testnet-pless-zkevm-node | CDK (Rollup) | rollup | N/A | ZkEVM Node:0.7.3⚠️, ZkEVM Prover:6.0.8✅ |
| cdk2 | Chain Configuration Test | unknown | N/A |  |
| combinations | Component Combination Test | unknown | N/A |  |
| custom-static-ports | Standard Test Configuration | unknown | N/A |  |
| custom-static-ports-cdk-erigon-sequencer-ds | Standard Test Configuration | unknown | N/A |  |
| default-static-ports | Standard Test Configuration | unknown | N/A |  |
| deploy-cdk-to-local-l1 | Standard Test Configuration | unknown | N/A |  |
| deploy-cdk-to-sepolia | Standard Test Configuration | unknown | N/A |  |
| deploy-local-l1 | Standard Test Configuration | unknown | N/A |  |
| fork11 | Fork unknown Test | unknown | N/A | Agglayer:0.2.0-rc.19🧪, Agglayer Contracts:7.0.0-rc.2-fork.11🧪, ZkEVM Node:0.7.0-fork11📌 (+1 more) |
| fork12 | Fork unknown Test | unknown | N/A | Agglayer Contracts:11.0.0-rc.2-fork.12🧪, ZkEVM Prover:8.0.0-RC16-fork.12🧪 |
| fork13 | Fork unknown Test | unknown | N/A | Agglayer Contracts:8.1.0-rc.2-fork.13🧪, ZkEVM Prover:9.0.0-RC3-fork.13🧪 |
| fork9 | Fork unknown Test | unknown | N/A | Agglayer:0.2.0-rc.19🧪, Agglayer Contracts:6.0.0-rc.1-fork.9🧪, CDK Validium Node:0.6.4-cdk.10⚠️ (+2 more) |
| rollup | CDK (Rollup) | rollup | N/A |  |
| validium | CDK (Cdk Validium) | cdk_validium | N/A |  |

### CDK-Erigon

| Scenario | Description | Consensus | Fork ID | Key Components |
|----------|-------------|-----------|---------|----------------|
| auto | CDK-Erigon (Cdk Validium) | cdk_validium | N/A | Agglayer Contracts:11.0.0-rc.2-fork.12🧪, ZkEVM Prover:8.0.0-RC16-fork.12🧪 |
| cdk-erigon | Standard Test Configuration | unknown | N/A |  |
| fork11-cdk-erigon-rollup | CDK-Erigon (Rollup) | rollup | N/A | Agglayer:0.2.0-rc.19🧪, Agglayer Contracts:7.0.0-rc.2-fork.11🧪, ZkEVM Node:0.7.0-fork11📌 (+1 more) |
| fork11-cdk-erigon-validium | CDK-Erigon (Cdk Validium) | cdk_validium | N/A | Agglayer:0.2.0-rc.19🧪, Agglayer Contracts:7.0.0-rc.2-fork.11🧪, ZkEVM Node:0.7.0-fork11📌 (+1 more) |
| fork12-cdk-erigon-rollup | CDK-Erigon (Rollup) | rollup | N/A | Agglayer Contracts:11.0.0-rc.2-fork.12🧪, ZkEVM Prover:8.0.0-RC16-fork.12🧪 |
| fork12-cdk-erigon-validium | CDK-Erigon (Cdk Validium) | cdk_validium | N/A | Agglayer Contracts:11.0.0-rc.2-fork.12🧪, ZkEVM Prover:8.0.0-RC16-fork.12🧪 |
| fork13-cdk-erigon-rollup | CDK-Erigon (Rollup) | rollup | N/A | Agglayer Contracts:8.1.0-rc.2-fork.13🧪, ZkEVM Prover:9.0.0-RC3-fork.13🧪 |
| fork13-cdk-erigon-validium | CDK-Erigon (Cdk Validium) | cdk_validium | N/A | Agglayer Contracts:8.1.0-rc.2-fork.13🧪, ZkEVM Prover:9.0.0-RC3-fork.13🧪 |
| fork9-cdk-erigon-rollup | CDK-Erigon (Rollup) | rollup | N/A | Agglayer:0.2.0-rc.19🧪, Agglayer Contracts:6.0.0-rc.1-fork.9🧪, CDK Validium Node:0.6.4-cdk.10⚠️ (+2 more) |
| fork9-cdk-erigon-validium | CDK-Erigon (Cdk Validium) | cdk_validium | N/A | Agglayer:0.2.0-rc.19🧪, Agglayer Contracts:6.0.0-rc.1-fork.9🧪, CDK Validium Node:0.6.4-cdk.10⚠️ (+2 more) |
| pre-deployed | CDK-Erigon (Cdk Validium) | cdk_validium | N/A | Agglayer Contracts:11.0.0-rc.2-fork.12🧪, ZkEVM Prover:8.0.0-RC16-fork.12🧪 |

### PP (Pessimistic Proofs)

| Scenario | Description | Consensus | Fork ID | Key Components |
|----------|-------------|-----------|---------|----------------|
| fork12-cdk-erigon-sovereign | PP (Pessimistic Proofs) | pessimistic | N/A | Agglayer Contracts:11.0.0-rc.2-fork.12🧪, ZkEVM Prover:8.0.0-RC16-fork.12🧪 |
| op-default | OP Stack Rollup | pessimistic | N/A |  |
| op2 | OP Stack Rollup | pessimistic | N/A |  |
| sovereign | PP (Pessimistic Proofs) | pessimistic | N/A |  |

### FEP (Full Execution Proofs)

| Scenario | Description | Consensus | Fork ID | Key Components |
|----------|-------------|-----------|---------|----------------|
| op-succinct | FEP (Full Execution Proofs) - OP Succinct | fep | N/A |  |
| op-succinct-real-prover | FEP (Full Execution Proofs) - OP Succinct | fep | N/A |  |


## Component Details

| Component | Current Version | Status | Latest Release | Source |
|-----------|----------------|--------|----------------|--------|
| AggKit | [0.5.0-beta3](https://github.com/agglayer/agglayer-contracts/releases/tag/v0.5.0-beta3) | experimental 🧪 | [v0.4.0](https://github.com/agglayer/aggkit/releases/tag/v0.4.0) | [GitHub](https://github.com/agglayer/agglayer-contracts) |
| AggKit Prover | [1.2.0](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v1.2.0) | deprecated ⚠️ | unknown | [GitHub](https://github.com/0xPolygonHermez/zkevm-prover) |
| Agglayer | [0.3.5](https://github.com/agglayer/agglayer-contracts/releases/tag/v0.3.5) | deprecated ⚠️ | [v0.3.5](https://github.com/agglayer/agglayer/releases/tag/v0.3.5) | [GitHub](https://github.com/agglayer/agglayer-contracts) |
| Agglayer Contracts | [11.0.0-rc.2-fork.12](https://github.com/agglayer/agglayer-contracts/releases/tag/v11.0.0-rc.2-fork.12) | experimental 🧪 | [v9.0.0](https://github.com/agglayer/agglayer-contracts/releases/tag/v9.0.0) | [GitHub](https://github.com/agglayer/agglayer-contracts) |
| Bridge Service | [0.6.2-RC2](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v0.6.2-RC2) | experimental 🧪 | [v0.6.1](https://github.com/0xPolygon/zkevm-bridge-service/releases/tag/v0.6.1) | [GitHub](https://github.com/0xPolygonHermez/zkevm-prover) |
| Bridge UI | [0006445](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v0006445) | stable ✅ | unknown | [GitHub](https://github.com/0xPolygonHermez/zkevm-prover) |
| CDK Erigon | [2.61.19](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v2.61.19) | deprecated ⚠️ | [v2.61.23](https://github.com/0xPolygon/cdk-erigon/releases/tag/v2.61.23) | [GitHub](https://github.com/0xPolygonHermez/cdk-erigon) |
| CDK Node | [0.5.4](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v0.5.4) | deprecated ⚠️ | [v0.5.4](https://github.com/0xPolygon/cdk/releases/tag/v0.5.4) | [GitHub](https://github.com/0xPolygonHermez/cdk-erigon) |
| CDK Validium Node | [0.6.4-cdk.10](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v0.6.4-cdk.10) | deprecated ⚠️ | [v0.6.7+cdk.2](https://github.com/0xPolygon/cdk-validium-node/releases/tag/v0.6.7%2Bcdk.2) | [GitHub](https://github.com/0xPolygonHermez/cdk-erigon) |
| Data Availability | [0.0.13](https://github.com/0xPolygonHermez/cdk-erigon/releases/tag/v0.0.13) | deprecated ⚠️ | unknown | [GitHub](https://github.com/0xPolygonHermez/cdk-erigon) |
| OP Succinct Proposer | [2.3.3-agglayer](https://github.com/agglayer/agglayer-contracts/releases/tag/v2.3.3-agglayer) | deprecated ⚠️ | unknown | [GitHub](https://github.com/agglayer/agglayer-contracts) |
| Pool Manager | [0.1.2](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v0.1.2) | deprecated ⚠️ | unknown | [GitHub](https://github.com/0xPolygonHermez/zkevm-prover) |
| Sequence Sender | [0.2.4](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v0.2.4) | deprecated ⚠️ | unknown | [GitHub](https://github.com/0xPolygonHermez/zkevm-prover) |
| Status Checker | 0.2.8 | deprecated ⚠️ | unknown | N/A |
| Test Runner | 9fe80e1 | stable ✅ | unknown | N/A |
| ZkEVM Node | [0.7.3](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v0.7.3) | deprecated ⚠️ | unknown | [GitHub](https://github.com/0xPolygonHermez/zkevm-prover) |
| ZkEVM Prover | [8.0.0-RC16-fork.12](https://github.com/0xPolygonHermez/zkevm-prover/releases/tag/v8.0.0-RC16-fork.12) | experimental 🧪 | [v6.0.2](https://github.com/0xPolygon/zkevm-prover/releases/tag/v6.0.2) | [GitHub](https://github.com/0xPolygonHermez/zkevm-prover) |

### Status Legend

- ✅ **Stable**: Production-ready, recommended for use
- ⚠️ **Deprecated**: No longer recommended, will be removed in future versions
- 🧪 **Experimental**: Under development, may have breaking changes
- 📌 **Pinned**: Specific version required due to compatibility or bug fixes