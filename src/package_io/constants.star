ADDITIONAL_SERVICES = struct(
    arpeggio="arpeggio",
    assertoor="assertoor",
    blockscout="blockscout",
    blutgang="blutgang",
    bridge_spammer="bridge_spammer",
    erpc="erpc",
    observability="observability",
    pless_zkevm_node="pless_zkevm_node",
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

SEQUENCER_TYPE = struct(
    CDK_ERIGON="erigon",
    ZKEVM="zkevm",
)

TOOLBOX_IMAGE = "leovct/toolbox:0.0.8"

L1_ENGINES = ("geth", "anvil")
