# The types of sequencers supported in Kurtosis CDK.
SEQUENCER_TYPES = struct(
    # The legacy sequencer used in zkEVM.
    zkevm_node="zkevm-node",
    # The new sequencer built on top of Erigon.
    cdk_erigon="cdk-erigon",
)


def is_zkevm_node_sequencer(args):
    return args["sequencer_type"] == SEQUENCER_TYPES.zkevm_node


def is_cdk_erigon_sequencer(args):
    return args["sequencer_type"] == SEQUENCER_TYPES.cdk_erigon


def get_sequencer_name(plan, args):
    return args["sequencer_type"] + "-sequencer" + args["deployment_suffix"]
