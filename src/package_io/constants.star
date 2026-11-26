ADDITIONAL_SERVICES = struct(
    agglogger="agglogger",
    aggkit_proxy="aggkit_proxy",
    arpeggio="arpeggio",
    assertoor="assertoor",
    blockscout="blockscout",
    blutgang="blutgang",
    bridge_ui="bridge_ui",
    bridge_spammer="bridge_spammer",
    erpc="erpc",
    observability="observability",
    rpc_fuzzer="rpc_fuzzer",
    status_checker="status_checker",
    test_runner="test_runner",
    tx_spammer="tx_spammer",
    agglayer_dashboard="agglayer_dashboard",
    zkevm_bridge_ui="zkevm_bridge_ui",
)

# Which backend the "bridge_ui" additional service uses for bridge/claim data:
# - bridge_hub (default): the bridge-hub stack (mongo, L1/L2 consumers, api)
#   behind the haproxy proxy.
# - aggkit: no bridge-hub stack, the haproxy proxy forwards to the aggkit bridge
#   REST API.
BRIDGE_UI_BACKEND = struct(
    bridge_hub="bridge_hub",
    aggkit="aggkit",
)

LOG_LEVEL = struct(
    error="error",
    warn="warn",
    info="info",
    debug="debug",
    trace="trace",
)

# op-deployer v0.10.0 needs an SP1 verifier exposing VERSION() on the L1. Devnets never submit
# ZK proofs, so the L1 genesis preloads Optimism's MockSP1Verifier (runtime code) at this address.
# Keep in sync with agglayer/optimism-package (`DEFAULT_SP1_VERIFIER`).
MOCK_SP1_VERIFIER_ADDRESS = "0x5100000000000000000000000000000000000001"
MOCK_SP1_VERIFIER_CODE = "0x608060405234801561001057600080fd5b50600436106100415760003560e01c80632a5104361461004657806341493c6014610079578063ffa1ad7414610090575b600080fd5b6040517f0d13b26f3ea578005da0af16c31e23911e3f8f5124005a1e77fa2a6477dc930e81526020015b60405180910390f35b61008e610087366004610118565b5050505050565b005b604080518082018252600b81527f76302e302e302d4d4f434b000000000000000000000000000000000000000000602082015290516100709190610192565b60008083601f8401126100e157600080fd5b50813567ffffffffffffffff8111156100f957600080fd5b60208301915083602082850101111561011157600080fd5b9250929050565b60008060008060006060868803121561013057600080fd5b85359450602086013567ffffffffffffffff8082111561014f57600080fd5b61015b89838a016100cf565b9096509450604088013591508082111561017457600080fd5b50610181888289016100cf565b969995985093965092949392505050565b600060208083528351808285015260005b818110156101bf578581018301518582016040015282016101a3565b818111156101d1576000604083870101525b50601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe01692909201604001939250505056fea164736f6c634300080f000a"

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
    op_reth="op-reth",
    anvil="anvil",
    besu="besu",
)

# The single-validator QBFT Besu node is both the sequencer (block proposer) and the RPC endpoint,
# so both mappings resolve to the same service.
L2_SEQUENCER_MAPPING = {
    SEQUENCER_TYPE.cdk_erigon: "cdk-erigon-sequencer",
    SEQUENCER_TYPE.op_reth: "op-el-1-op-reth-op-node",
    # Anvil runs a single node which is both the sequencer and the RPC.
    SEQUENCER_TYPE.anvil: "l2-anvil",
    SEQUENCER_TYPE.besu: "besu",
}

L2_RPC_MAPPING = {
    SEQUENCER_TYPE.cdk_erigon: "cdk-erigon-rpc",
    SEQUENCER_TYPE.op_reth: "op-el-2-op-reth-op-node",
    SEQUENCER_TYPE.anvil: "l2-anvil",
    SEQUENCER_TYPE.besu: "besu",
}

# Stacks whose L2 contracts are predeployed through the sovereign genesis
# pipeline (create_sovereign_rollup_predeployed -> create_predeployed_op_genesis)
# rather than deployed by an L1 rollup-creation script.
SOVEREIGN_SEQUENCER_TYPES = [
    SEQUENCER_TYPE.op_reth,
    SEQUENCER_TYPE.anvil,
    SEQUENCER_TYPE.besu,
]

FORK_ID_TO_NAME = {
    9: "elderberry",
    11: "elderberry",
    12: "banana",
    13: "banana",
}

TOOLBOX_IMAGE = (
    "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/toolbox:0.0.14"
)

# Anvil's built-in development mnemonic. The anvil L2 is prefunded from it, and
# contracts.sh derives its L2 funding key from the same mnemonic.
ANVIL_DEFAULT_MNEMONIC = "test test test test test test test test test test test junk"

L1_ENGINE = struct(
    ethereum_package="ethereum-package",
    anvil="anvil",
)

VALID_AGGKIT_TRIGGER_CERT_MODES = struct(
    epoch_based="EpochBased",
    new_bridge="NewBridge",
    asap="ASAP",
    auto="Auto",
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
    "aggkit_image": "ghcr.io/agglayer/aggkit:0.12.0-rc5",
    "aggkit_prover_image": "ghcr.io/agglayer/aggkit-prover:2.3.0",
    "agglayer_image": "ghcr.io/agglayer/agglayer:1.0.0",
    "agglayer_contracts_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-contracts:v12.2.3-r3",
    # Used by bridge_ui_backend "bridge_hub" (ui.star run_server): a container that
    # reads a rendered config.ts. Not the same image as agglayer_dev_ui_aggkit_image.
    "agglayer_dev_ui_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-dev-ui:844bfbc",
    # agglayer-dev-ui for bridge_ui_backend "aggkit" (ui.star run_dev_ui): an
    # nginx image configured through a mounted /etc/agglayer-dev-ui/config.json,
    # whose strict schema is rendered by
    # static_files/additional_services/bridge-ui/aggkit-dev-ui-config.json.tmpl.
    "agglayer_dev_ui_aggkit_image": "ghcr.io/agglayer/agglayer-dev-ui:0.1.2",
    "agglogger_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglogger:bf1f8c1",
    # Anvil >= v1.5.0 is required: agglayer's settlement task calls
    # eth_getTransactionBySenderAndNonce, which older versions answer with
    # "Method not found" and agglayer then panics.
    "anvil_image": "ghcr.io/foundry-rs/foundry:v1.10.0",
    "besu_image": "hyperledger/besu:26.11.2",
    "bridge_hub_api_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/bridge-hub-api:2a71905",
    "bridge_hub_consumer_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/bridge-hub-consumer:2a71905",
    "bridge_hub_autoclaim_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/bridge-hub-autoclaim:2a71905",
    "cdk_erigon_image": "ghcr.io/0xpolygon/cdk-erigon:v2.61.24",
    # Type 1 cdk-erigon sovereign image.
    # The cdk_erigon_sovereign_image is provided for reference only and is not actively used in this package.
    # For example: .github/tests/cdk-erigon/sovereign-ecdsa-multisig.yml
    "cdk_erigon_sovereign_image": "ghcr.io/0xpolygon/cdk-erigon:v2.65.0-RC3",
    # cdk 0.5.4 patched to use node-reported L1 block hashes (go-ethereum 1.15 does not hash Amsterdam headers).
    "cdk_node_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/cdk:v0.5.4-cdk-amsterdam",
    "db_image": "postgres:17.6",
    "mongodb_image": "mongo:7.0.29",
    "geth_image": "ethereum/client-go:v1.17.10",
    "reth_image": "ghcr.io/paradigmxyz/reth:v2.11.0",
    "lighthouse_image": "sigp/lighthouse:v8.3.3",
    "mitm_image": "mitmproxy/mitmproxy:12.3.1",
    "op_batcher_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-batcher:v1.19.0",
    "op_contract_deployer_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/op-deployer:v0.10.0-cdk",
    "op_reth_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-reth:v2.10.0",
    "op_node_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.21.0",
    "op_proposer_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-proposer:v1.17.1",
    # Pinned to v3.10.0: aggkit-prover 2.2.x/2.3.x embed the op-succinct-elfs from this
    # version, and it hard-fails at startup if the aggregation vkey baked into the
    # AggchainFEP contract (via fetch-l2oo-config, taken from this image) does not
    # match its own. Bump both together once a newer aggkit-prover ships.
    "op_succinct_proposer_image": "ghcr.io/agglayer/op-succinct/op-succinct-agglayer:v3.10.0-agglayer",
    "status_checker_image": "ghcr.io/0xpolygon/status-checker:v0.2.10",
    "test_runner_image": "ghcr.io/agglayer/e2e:dda31ee",
    "cdk_data_availability_image": "ghcr.io/0xpolygon/cdk-data-availability:0.0.13",
    "zkevm_bridge_proxy_image": "haproxy:3.2-bookworm",
    "zkevm_bridge_service_image": "ghcr.io/0xpolygon/zkevm-bridge-service:v0.6.4-RC5",
    "zkevm_bridge_ui_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/zkevm-bridge-ui:3f1a3a0",
    "zkevm_pool_manager_image": "ghcr.io/0xpolygon/zkevm-pool-manager:0.1.3",
    "zkevm_prover_image": "hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12",
}

# op-node image used by default when OP Succinct is deployed. op-node v1.19.6 and later
# no longer return `cross_unsafe_l2` from `optimism_syncStatus`, which the OP Succinct
# proposer (v3.10.0) still requires, so every range proof fails. Move this to the
# default op-node image once the proposer image is bumped to a release that tolerates
# the missing field.
OP_SUCCINCT_OP_NODE_IMAGE = (
    "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.19.5"
)
