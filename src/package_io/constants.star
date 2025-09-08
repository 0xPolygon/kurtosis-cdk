ADDITIONAL_SERVICES = struct(
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
    "europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/toolbox:0.0.10"
)

L1_ENGINES = ("geth", "anvil")

# Standard zero address in Ethereum.
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
