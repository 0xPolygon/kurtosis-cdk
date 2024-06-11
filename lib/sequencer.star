# The types of sequencers supported in Kurtosis CDK.
SEQUENCER_TYPES = struct(
    # The legacy sequencer used in zkEVM.
    zkevm_node="zkevm-node",
    # The new sequencer built on top of Erigon.
    cdk_erigon="cdk-erigon",
)


def is_cdk_erigon_sequencer(args):
    return args["sequencer_type"] == SEQUENCER_TYPES.cdk_erigon


def get_sequencer_name(args):
    return args["sequencer_type"] + "-sequencer" + args["deployment_suffix"]


def get_l2_rpc_name(args):
    return args["sequencer_type"] + "-rpc" + args["deployment_suffix"]


def get_sequencer_rpc_url(plan, args):
    sequencer_name = get_sequencer_name(args)
    sequencer_service = plan.get_service(name=sequencer_name)
    return "http://{}:{}".format(
        sequencer_service.ip_address, sequencer_service.ports["rpc"].number
    )
