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

# Which backend the "bridge_ui" additional service should use to source
# bridge/claim data:
# - bridge_hub: deploy the full bridge-hub stack (mongo + L1/L2 consumers +
#   api + autoclaimer) fronted by the haproxy proxy. This is the legacy
#   default.
# - aggkit: skip the bridge-hub stack entirely and have the haproxy proxy
#   forward directly to the aggkit bridge REST API.
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
)

L2_SEQUENCER_MAPPING = {
    SEQUENCER_TYPE.cdk_erigon: "cdk-erigon-sequencer",
    SEQUENCER_TYPE.op_reth: "op-el-1-op-reth-op-node",
    # Anvil runs a single node which is both the sequencer and the RPC.
    SEQUENCER_TYPE.anvil: "l2-anvil",
}

L2_RPC_MAPPING = {
    SEQUENCER_TYPE.cdk_erigon: "cdk-erigon-rpc",
    SEQUENCER_TYPE.op_reth: "op-el-2-op-reth-op-node",
    SEQUENCER_TYPE.anvil: "l2-anvil",
}

# Stacks whose L2 contracts are predeployed through the sovereign genesis
# pipeline (create_sovereign_rollup_predeployed -> create_predeployed_op_genesis)
# rather than deployed by an L1 rollup-creation script.
SOVEREIGN_SEQUENCER_TYPES = [
    SEQUENCER_TYPE.op_reth,
    SEQUENCER_TYPE.anvil,
]

FORK_ID_TO_NAME = {
    9: "elderberry",
    11: "elderberry",
    12: "banana",
    13: "banana",
}

TOOLBOX_IMAGE = (
    "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/toolbox:0.0.12"
)

# Anvil's built-in development mnemonic. Used as the default for the anvil L2
# (sequencer_type: anvil) because static_files/contracts/contracts.sh's
# initialize_rollup derives its L2 funding key from exactly this mnemonic.
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
    "aggkit_image": "ghcr.io/agglayer/aggkit:0.10.0-rc7",
    "aggkit_prover_image": "ghcr.io/agglayer/aggkit-prover:2.1.0",
    # NOTE: v0.6.0-rc.8 is the upstream git tag name; the published GHCR image
    # tag omits the "v" prefix (verified via GET
    # https://ghcr.io/v2/agglayer/agglayer/tags/list?n=1000 -- the tag list
    # contains "0.6.0-rc.8", not "v0.6.0-rc.8").
    "agglayer_image": "ghcr.io/agglayer/agglayer:0.6.0-rc.8",
    "agglayer_contracts_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-contracts:v12.2.3",
    # bridge_ui_backend "bridge_hub" mode only (src/additional_services/
    # bridge_ui/ui.star run_server): mounts a rendered config.ts and expects
    # a Next-dev-server-style container. Deliberately left unbumped -- see
    # agglayer_dev_ui_aggkit_image below for why this key and that one are
    # NOT the same image.
    "agglayer_dev_ui_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglayer-dev-ui:844bfbc",
    # S5 (dev-ui-ci-snapshot plan, D4): the published GHCR image built from
    # agglayer/agglayer-dev-ui's feat/aggkit-backend branch (PR #24), which
    # understands the aggkit bridge REST API and is configured at runtime via
    # a mounted /etc/agglayer-dev-ui/config.json (contract: dev-ui
    # docs/docker.md -- nginx:alpine runtime, no Node, no config.ts support).
    # Consumed as a published tag only -- no source build here.
    #
    # Deliberately a SEPARATE constant from agglayer_dev_ui_image above, not
    # a bump of it: that key is also read by run_server() (bridge_ui_backend
    # "bridge_hub" mode), which mounts a rendered config.ts for a
    # Next-dev-server-style container -- a different runtime contract that
    # this GHCR image's nginx:alpine runtime cannot serve (no Node.js, no
    # config.ts support, and it requires config.json at a different path).
    # Point-bumping the shared key would silently break
    # .github/tests/additional-services.yml's bridge_hub-mode bridge_ui
    # deployment (wired into .github/workflows/test.yml and nightly.yml) --
    # the exact regression this step's "no behavior change to existing"
    # acceptance criterion forbids. See
    # src/additional_services/bridge_ui/ui.star's new run_dev_ui(), used only
    # by the opt-in aggkit-mode dev-ui deployment (aggkit_deploy_dev_ui).
    "agglayer_dev_ui_aggkit_image": "ghcr.io/agglayer/agglayer-dev-ui:dispatch-feat-aggkit-backend-dd070d7db256-31574163188",
    "agglogger_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/agglogger:bf1f8c1",
    # foundry >= v1.5.0 is REQUIRED when the L1 is anvil: agglayer's settlement
    # task probes nonce inclusion with `eth_getTransactionBySenderAndNonce`
    # after sending the verify tx. anvil only gained that method in v1.5.0
    # (v1.4.x answers -32601 "Method not found"), which agglayer treats as
    # "assumed non-recoverable" and panics on
    # (agglayer-settlement-service/src/settlement_task.rs:543), leaving every
    # certificate stuck in `InError` even though the settlement tx itself
    # landed on L1. See plans/dev-ui-ci-snapshot/s4b-evidence/.
    "anvil_image": "ghcr.io/foundry-rs/foundry:v1.5.1",
    "bridge_hub_api_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/bridge-hub-api:2a71905",
    "bridge_hub_consumer_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/bridge-hub-consumer:2a71905",
    "bridge_hub_autoclaim_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/bridge-hub-autoclaim:2a71905",
    "cdk_erigon_image": "ghcr.io/0xpolygon/cdk-erigon:v2.61.24",
    # Type 1 cdk-erigon sovereign image.
    # The cdk_erigon_sovereign_image is provided for reference only and is not actively used in this package.
    # For example: .github/tests/cdk-erigon/sovereign-ecdsa-multisig.yml
    "cdk_erigon_sovereign_image": "ghcr.io/0xpolygon/cdk-erigon:v2.65.0-RC3",
    "cdk_node_image": "ghcr.io/0xpolygon/cdk:0.5.4",
    "db_image": "postgres:17.6",
    "mongodb_image": "mongo:7.0.29",
    "geth_image": "ethereum/client-go:v1.17.5",
    "reth_image": "ghcr.io/paradigmxyz/reth:v2.4.1",
    "lighthouse_image": "sigp/lighthouse:v8.2.1",
    "mitm_image": "mitmproxy/mitmproxy:11.1.3",
    "op_batcher_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-batcher:v1.16.12",
    "op_contract_deployer_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/op-deployer:v0.7.1-cdk",
    "op_reth_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-reth:v2.4.1",
    "op_node_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-node:v1.19.4",
    "op_proposer_image": "us-docker.pkg.dev/oplabs-tools-artifacts/images/op-proposer:v1.16.3",
    # Pinned to v3.10.0: aggkit-prover 2.1.0 embeds the op-succinct-elfs from this
    # version, and it hard-fails at startup if the aggregation vkey baked into the
    # AggchainFEP contract (via fetch-l2oo-config, taken from this image) does not
    # match its own. Bump both together once a newer aggkit-prover ships.
    "op_succinct_proposer_image": "ghcr.io/agglayer/op-succinct/op-succinct-agglayer:v3.10.0-agglayer",
    "status_checker_image": "ghcr.io/0xpolygon/status-checker:v0.2.9",
    "test_runner_image": "ghcr.io/agglayer/e2e:dda31ee",
    "cdk_data_availability_image": "ghcr.io/0xpolygon/cdk-data-availability:0.0.13",
    "zkevm_bridge_proxy_image": "haproxy:3.2-bookworm",
    "zkevm_bridge_service_image": "ghcr.io/0xpolygon/zkevm-bridge-service:v0.6.4-RC2",
    "zkevm_bridge_ui_image": "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/zkevm-bridge-ui:3f1a3a0",
    "zkevm_pool_manager_image": "ghcr.io/0xpolygon/zkevm-pool-manager:0.1.3",
    "zkevm_prover_image": "hermeznetwork/zkevm-prover:v8.0.0-RC16-fork.12",
}
