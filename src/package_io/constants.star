ADDITIONAL_SERVICES = struct(
    agglogger="agglogger",
    arpeggio="arpeggio",
    assertoor="assertoor",
    blockscout="blockscout",
    blutgang="blutgang",
    bridge_spammer="bridge_spammer",
    erpc="erpc",
    observability="observability",
    pless_zkevm_node="pless_zkevm_node",
    rpc_fuzzer="rpc_fuzzer",
    status_checker="status_checker",
    test_runner="test_runner",
    tx_spammer="tx_spammer",
    agglayer_dashboard="agglayer_dashboard",
)

LOG_LEVEL = struct(
    error="error",
    warn="warn",
    info="info",
    debug="debug",
    trace="trace",
)

CONSENSUS_TYPE = struct(
    rollup="rollup",
    cdk_validium="cdk_validium",
    pessimistic="pessimistic",
    ecdsa_multisig="ecdsa_multisig",
    fep="fep",
)

SEQUENCER_TYPE = struct(
    CDK_ERIGON="erigon",
    ZKEVM="zkevm",
)

TOOLBOX_IMAGE = (
    "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/toolbox:0.0.12"
)

L1_ENGINES = ("geth", "anvil")

# Standard zero address in Ethereum.
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

DEFAULT_IMAGES = {
    "aggkit_image": "ghcr.io/agglayer/aggkit:0.5.0-beta4",
    "aggkit_prover_image": "ghcr.io/agglayer/aggkit-prover:1.2.0",
    "agglayer_image": "ghcr.io/agglayer/agglayer:0.3.5",
    "agglayer_contracts_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-contracts:v11.0.0-rc.2-fork.12",
    "agglogger_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglogger:bf1f8c1",
    "anvil_image": "ghcr.io/foundry-rs/foundry:v1.0.0",
    "cdk_erigon_node_image": "hermeznetwork/cdk-erigon:v2.61.24",
    "cdk_sovereign_erigon_node_image": "hermeznetwork/cdk-erigon:v2.63.0-rc4",  # Type-1 CDK Erigon Sovereign
    "cdk_node_image": "ghcr.io/0xpolygon/cdk:0.5.4",
    "cdk_validium_node_image": "ghcr.io/0xpolygon/cdk-validium-node:0.6.4-cdk.10",
    "db_image": "postgres:16.2",
    "geth_image": "ethereum/client-go:v1.16.2",
    "lighthouse_image": "sigp/lighthouse:v7.1.0",
    "mitm_image": "mitmproxy/mitmproxy:11.1.3",
    "op_batcher_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-batcher:v1.15.0",
    "op_contract_deployer_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/op-deployer:v0.4.0-rc.2",
    "op_geth_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101511.1",
    "op_node_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.13.5",
    "op_proposer_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-proposer:v1.10.0",
    "op_succinct_proposer_image": "ghcr.io/agglayer/op-succinct/op-succinct:v2.3.3-agglayer",
    "status_checker_image": "ghcr.io/0xpolygon/status-checker:v0.2.8",
    "test_runner_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/e2e:9fe80e1",
    "zkevm_da_image": "ghcr.io/0xpolygon/cdk-data-availability:0.0.13",
    "zkevm_bridge_proxy_image": "haproxy:3.1-bookworm",
    "zkevm_bridge_service_image": "hermeznetwork/zkevm-bridge-service:v0.6.2-RC2",
    "zkevm_bridge_ui_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/zkevm-bridge-ui:0006445",
    "zkevm_node_image": "hermeznetwork/zkevm-node:v0.7.3",
    "zkevm_pool_manager_image": "hermeznetwork/zkevm-pool-manager:v0.1.2",
    "zkevm_prover_image": "hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12",
    "zkevm_sequence_sender_image": "hermeznetwork/zkevm-sequence-sender:v0.2.4",
}
