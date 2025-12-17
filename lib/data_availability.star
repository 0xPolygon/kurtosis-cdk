# The types of data availability (DA) modes supported in Kurtosis CDK.
# In the future, we would like to support external DA protocols such as Avail, Celestia and Near.
DATA_AVAILABILITY_MODES = struct(
    # In rollup mode, transaction data is stored on-chain on L1.
    rollup="rollup",
    # In cdk-validium mode, transaction data is stored off-chain using the CDK DA layer and a DAC.
    cdk_validium="cdk_validium",
    # In pessimistic mode, the contracts don't require full execution proofs. Instead we use the PP to ensure the integrity of bridging
    pessimistic="pessimistic",
)

AGGCHAIN_CONTRACT_NAMES = struct(
    # Aggchain using an ecdsa_multisig signature with CONSENSUS_TYPE = 1
    ecdsa_multisig="ecdsa_multisig",
    # Generic aggchain using Full Execution Proofs that relies on op-succinct stack.
    fep="fep",
)

# Map data availability modes and aggchain contract names to consensus contracts.
CONSENSUS_CONTRACTS = {
    DATA_AVAILABILITY_MODES.rollup: "PolygonZkEVMEtrog",
    DATA_AVAILABILITY_MODES.cdk_validium: "PolygonValidiumEtrog",
    DATA_AVAILABILITY_MODES.pessimistic: "PolygonPessimisticConsensus",
    AGGCHAIN_CONTRACT_NAMES.ecdsa_multisig: "AggchainECDSAMultisig",
    AGGCHAIN_CONTRACT_NAMES.fep: "AggchainFEP",
}


def get_consensus_contract(args):
    return CONSENSUS_CONTRACTS.get(args["consensus_contract_type"])


def is_cdk_validium(args):
    return args["consensus_contract_type"] == DATA_AVAILABILITY_MODES.cdk_validium
