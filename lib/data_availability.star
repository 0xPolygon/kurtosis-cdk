# The types of data availability (DA) modes supported in Kurtosis CDK.
# In the future, we would like to support external DA protocols such as Avail, Celestia and Near.
DATA_AVAILABILITY_MODES = struct(
    # In rollup mode, transaction data is stored on-chain on L1.
    rollup="rollup",
    # In cdk-validium mode, transaction data is stored off-chain using the CDK DA layer and a DAC.
    cdk_validium="cdk-validium",
)

# Map data availability modes to consensus contracts.
CONSENSUS_CONTRACTS = {
    DATA_AVAILABILITY_MODES.rollup: "PolygonZkEVMEtrog",
    DATA_AVAILABILITY_MODES.cdk_validium: "PolygonValidiumEtrog",
}


def get_node_image(args):
    # Map data availability modes to node images.
    node_images = {
        DATA_AVAILABILITY_MODES.rollup: args["zkevm_node_image"],
        DATA_AVAILABILITY_MODES.cdk_validium: args["cdk_node_image"],
    }
    return node_images.get(args["data_availability_mode"])


def get_consensus_contract(args):
    return CONSENSUS_CONTRACTS.get(args["data_availability_mode"])


def is_cdk_validium(args):
    return args["data_availability_mode"] == DATA_AVAILABILITY_MODES.cdk_validium
