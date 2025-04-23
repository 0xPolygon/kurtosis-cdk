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

# Standard zero address in Ethereum.
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

# 256-bit zero hash.
ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000"
