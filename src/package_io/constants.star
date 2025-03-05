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
