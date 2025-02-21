# OP Sovereign Rollup

## Deploying OP Rollup

Change the `deploy_optimism_rollup` parameter to `True` and `consensus_contract_type` to `pessimistic`:

```
DEFAULT_DEPLOYMENT_STAGES = {
    ...
    "deploy_optimism_rollup": True,
    ...
}

...

DEFAULT_ARGS = (
    {
        ...
        "consensus_contract_type": "pessimistic",
        ...
    }
)
```

## Deploying OP Succinct

This requires more precise configuration to correctly run. Reference the below parameters - the `DEFAULT_OP_STACK_ARGS` versions must be exact:

```
DEFAULT_DEPLOYMENT_STAGES = {
    ...
    "deploy_optimism_rollup": True,
    # After deploying OP Stack, upgrade it to OP Succinct.
    # Even mock-verifier deployments require an actual SPN network key.
    "deploy_op_succinct": True,
    ...
}

...

DEFAULT_ARGS = (
    {
        ...
        "consensus_contract_type": "pessimistic",
        ...
    }
)

...

DEFAULT_ROLLUP_ARGS = {
    "agglayer_prover_sp1_key": <VALID_SPN_KEY>,
}

...

DEFAULT_OP_STACK_ARGS = {
    "chains": [
        {
            "participants": [
                {
                    "el_type": "op-geth",
                    "el_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101411.3",
                    "cl_type": "op-node",
                    "cl_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.10.1",
                    "count": 1,
                },
            ],
            "batcher_params": {
                "image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-batcher:v1.10.0",
            },
            "proposer_params": {
                "image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-proposer:v1.9.5",
            },
        },
    ],
    "op_contract_deployer_params": {
        "image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-deployer:v0.0.11",
        "l1_artifacts_locator": "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-c193a1863182092bc6cb723e523e8313a0f4b6e9c9636513927f1db74c047c15.tar.gz",
        "l2_artifacts_locator": "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-c193a1863182092bc6cb723e523e8313a0f4b6e9c9636513927f1db74c047c15.tar.gz",
    },
}

```

## Sovereign Bridging Sequence Diagram
```mermaid
---
title: "L1 -> L2 Sovereign Bridge Flow"
---
sequenceDiagram
    participant L1User as L1 User
    participant L1BridgeContract as L1BridgeContract
    participant L1InfoTreeSync as L1InfoTreeSync
    participant AggOracle as AggOracle
    participant L1GERContract as L1GERContract
    participant L2GERManager as L2GERManager
    participant BridgeService as Bridge Service
    participant L2SovereignBridge as L2SovereignBridgeContract
    participant ClaimTxnManager as ClaimTxnManager
    participant L2User as L2 User

    L1User->>L1BridgeContract: bridgeAsset()
    L1BridgeContract->>L1InfoTreeSync: Updated GER
    L1InfoTreeSync->>AggOracle: Send data
    L1BridgeContract->>L1GERContract: Updated GER
    AggOracle->>L1GERContract: GetLastGlobalExitRoot()
    AggOracle->>L2GERManager: IsGERInjected()
    BridgeService->>L2SovereignBridge: MonitorTxs()
    L2SovereignBridge->>L2GERManager: Fetch GER
    ClaimTxnManager->>L2SovereignBridge: Autoclaim
    ClaimTxnManager->>L2User: processDepositStatus()

```

---

```mermaid
---
title: "L2 Sovereign -> L1 Bridge Flow"
---
sequenceDiagram
    participant L2User as L2 User
    participant L2SovereignBridge as L2SovereignBridgeContract
    participant L2BridgeSyncer as L2BridgeSyncer
    participant AggSender as AggSender
    participant AggLayer as AggLayer
    participant AggOracle as AggOracle
    participant L2GERManager as L2GERManager
    participant L1GERManager as L1GERManager
    participant L1BridgeContract as L1BridgeContract
    participant L1User as L1 User

    L2User->>L2SovereignBridge: bridgeAsset()
    L2SovereignBridge->>L2BridgeSyncer: GetLastProcessedBlock()
    L2BridgeSyncer->>AggSender: Update Certificate Status
    AggSender->>AggLayer: sendCertificate()
    AggLayer->>AggOracle: Updated State for L2
    AggOracle->>L2GERManager: InjectGER()
    AggLayer->>L1GERManager: Update GER
    L1GERManager->>L1BridgeContract: Ready for Claim
    L1User->>L1BridgeContract: claimAsset()

```