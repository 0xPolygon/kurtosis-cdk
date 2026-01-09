ADDITIONAL_SERVICES = struct(
    agglogger="agglogger",
    arpeggio="arpeggio",
    assertoor="assertoor",
    blockscout="blockscout",
    blutgang="blutgang",
    bridge_spammer="bridge_spammer",
    erpc="erpc",
    observability="observability",
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

LOG_FORMAT = struct(
    json="json",
    pretty="pretty",
)

CONSENSUS_TYPE = struct(
    rollup="rollup",
    cdk_validium="cdk-validium",
    pessimistic="pessimistic",
    ecdsa_multisig="ecdsa-multisig",
    fep="fep",
)

CONSENSUS_TYPE_TO_CONTRACT_MAPPING = {
    CONSENSUS_TYPE.rollup: "PolygonZkEVMEtrog",
    CONSENSUS_TYPE.cdk_validium: "PolygonValidiumEtrog",
    CONSENSUS_TYPE.pessimistic: "PolygonPessimisticConsensus",
    CONSENSUS_TYPE.ecdsa_multisig: "AggchainECDSAMultisig",
    CONSENSUS_TYPE.fep: "AggchainFEP",
}

SEQUENCER_TYPE = struct(
    cdk_erigon="cdk-erigon",
    op_geth="op-geth",
)

L2_SEQUENCER_MAPPING = {
    SEQUENCER_TYPE.cdk_erigon: "cdk-erigon-sequencer",
    SEQUENCER_TYPE.op_geth: "op-el-1-op-geth-op-node",
}

L2_RPC_MAPPING = {
    SEQUENCER_TYPE.cdk_erigon: "cdk-erigon-rpc",
    # SEQUENCER_TYPE.op_geth: "op-el-2-op-geth-op-node",
    SEQUENCER_TYPE.op_geth: "op-el-1-op-geth-op-node",
}

FORK_ID_TO_NAME = {
    9: "elderberry",
    11: "elderberry",
    12: "banana",
    13: "banana",
}

TOOLBOX_IMAGE = (
    "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/toolbox:0.0.12"
)

L1_ENGINE = struct(
    geth="geth",
    anvil="anvil",
)

# Standard zero address in Ethereum.
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

# Contracts folders
KEYSTORES_DIR = "/opt/keystores"
CONTRACTS_DIR = "/opt/agglayer-contracts"
OUTPUT_DIR = "/opt/output"
INPUT_DIR = "/opt/input"
SCRIPTS_DIR = "/opt/scripts"

DEFAULT_IMAGES = {
    "aggkit_image": "ghcr.io/agglayer/aggkit:0.8.0-beta6",
    "aggkit_prover_image": "ghcr.io/agglayer/aggkit-prover:1.9.1",
    "agglayer_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer:0.4.4-remove-agglayer-prover",
    "agglayer_contracts_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-contracts:v12.2.1",
    "agglogger_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglogger:bf1f8c1",
    "anvil_image": "ghcr.io/foundry-rs/foundry:v1.4.3",
    "cdk_erigon_image": "ghcr.io/0xpolygon/cdk-erigon:v2.61.24",
    # Type 1 cdk-erigon sovereign image.
    # The cdk_erigon_sovereign_image is provided for reference only and is not actively used in this package.
    # For example: .github/tests/cdk-erigon/sovereign-ecdsa-multisig.yml
    "cdk_erigon_sovereign_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/cdk-erigon:v2.65.0-RC1",
    "cdk_node_image": "ghcr.io/0xpolygon/cdk:0.5.4",
    "db_image": "postgres:17.6",
    "geth_image": "ethereum/client-go:v1.16.7",
    "lighthouse_image": "sigp/lighthouse:v8.0.1",
    "mitm_image": "mitmproxy/mitmproxy:11.1.3",
    "op_batcher_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-batcher:v1.16.3",
    "op_contract_deployer_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/op-deployer:v0.6.0-rc.2-cdk",
    "op_geth_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-geth:v1.101604.0",
    "op_node_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.16.4",
    "op_proposer_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-proposer:v1.10.0",
    "op_succinct_proposer_image": "ghcr.io/agglayer/op-succinct/op-succinct-agglayer:v3.4.0-rc.1-agglayer",
    "status_checker_image": "ghcr.io/0xpolygon/status-checker:v0.2.8",
    "test_runner_image": "ghcr.io/agglayer/e2e:dda31ee",
    "cdk_data_availability_image": "ghcr.io/0xpolygon/cdk-data-availability:0.0.13",
    "zkevm_bridge_proxy_image": "haproxy:3.2-bookworm",
    "zkevm_bridge_service_image": "ghcr.io/0xpolygon/zkevm-bridge-service:v0.6.4-RC1",
    "zkevm_bridge_ui_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/zkevm-bridge-ui:0006445",
    "zkevm_pool_manager_image": "ghcr.io/0xpolygon/zkevm-pool-manager:0.1.3",
    "zkevm_prover_image": "hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12",
}
