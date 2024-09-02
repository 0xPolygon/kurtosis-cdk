GLOBAL_LOG_LEVEL = struct(
    error="error",
    warn="warn",
    info="info",
    debug="debug",
    trace="trace",
)

SEQUENCER_TYPE = struct(
    erigon="erigon",
    zkevm="zkevm",
)

SEQUENCE_SENDER_AGGREGATOR_TYPE = struct(
    cdk="cdk",
    legacy_zkevm="legacy-zkevm",
    new_zkevm="new-zkevm",
)
