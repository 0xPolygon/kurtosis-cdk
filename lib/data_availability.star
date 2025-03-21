# The types of data availability (DA) modes supported in Kurtosis CDK.
# In the future, we would like to support external DA protocols such as Avail, Celestia and Near.
DATA_AVAILABILITY_MODES = struct(
    # In rollup mode, transaction data is stored on-chain on L1.
    rollup="rollup",
    # In cdk-validium mode, transaction data is stored off-chain using the CDK DA layer and a DAC.
    cdk_validium="cdk-validium",
    # In pessimistic mode, the contracts don't require full execution proofs. Instead we use the PP to ensure the integrity of bridging
    pessimistic="pessimistic",
)

AGGCHAIN_CONTRACT_NAMES = struct(
    # Aggchain using an ECDSA signature with CONSENSUS_TYPE = 1
    ecdsa="ecdsa",
    # Generic aggchain using Full Execution Proofs that relies on op-succinct stack.
    fep="fep",
)

# Map data availability modes and aggchain contract names to consensus contracts.
CONSENSUS_CONTRACTS = {
    DATA_AVAILABILITY_MODES.rollup: "PolygonZkEVMEtrog",
    DATA_AVAILABILITY_MODES.cdk_validium: "PolygonValidiumEtrog",
    DATA_AVAILABILITY_MODES.pessimistic: "PolygonPessimisticConsensus",
    AGGCHAIN_CONTRACT_NAMES.ecdsa: "AggchainECDSA",
    AGGCHAIN_CONTRACT_NAMES.fep: "AggchainFEP",
}


def get_node_image(args):
    # Map data availability modes to node images.
    node_images = {
        DATA_AVAILABILITY_MODES.rollup: args["zkevm_node_image"],
        DATA_AVAILABILITY_MODES.cdk_validium: args["cdk_validium_node_image"],
    }
    return node_images.get(args["consensus_contract_type"])


def get_consensus_contract(args):
    return CONSENSUS_CONTRACTS.get(args["consensus_contract_type"])


def is_cdk_validium(args):
    return args["consensus_contract_type"] == DATA_AVAILABILITY_MODES.cdk_validium
