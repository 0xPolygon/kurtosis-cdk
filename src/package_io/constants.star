LOG_LEVEL = struct(
    error="error",
    warn="warn",
    info="info",
    debug="debug",
    trace="trace",
)

L1_TYPE = struct(
    ETHEREUM_PKG="ethereum-pkg",
    ANVIL="anvil",
)

SEQUENCER_TYPE = struct(
    CDK_ERIGON="erigon",
    ZKEVM="zkevm",
)

TX_SPAMMER_IMG = "leovct/toolbox:0.0.5"
