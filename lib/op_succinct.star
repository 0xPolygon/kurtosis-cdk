# The VERIFIER_ADDRESS, L2OO_ADDRESS will need to be dynamically parsed from the output of the contract deployer
# NETWORK_PRIVATE_KEY must be from user input
def create_op_succinct_proposer_service_config(args, l1_genesis_artifact):
    op_succinct_name = "op-succinct-proposer" + args["deployment_suffix"]
    ports = get_op_succinct_proposer_ports(args)

    # TODO understand why the PRIVATE_KEY needs to be set and if it actually need to be the sequencer key... The value 0xc797616a567ffd3f7d80f110f4c19900e55258ac2aa96d96ded790e0bd727458 is made up just to ensure that the value isn't needed
    env_vars = {
        "L1_RPC": args["l1_rpc_url"],
        "L1_BEACON_RPC": args["l1_beacon_url"],
        "L2_RPC": args["op_el_rpc_url"],
        "L2_NODE_RPC": args["op_cl_rpc_url"],
        "PRIVATE_KEY": "0xc797616a567ffd3f7d80f110f4c19900e55258ac2aa96d96ded790e0bd727458",
        "ETHERSCAN_API_KEY": "",
        "VERIFIER_ADDRESS": args["agglayer_gateway_address"],
        "AGG_PROOF_MODE": args["op_succinct_agg_proof_mode"],
        "L2OO_ADDRESS": args["zkevm_rollup_address"],
        "OP_SUCCINCT_MOCK": args["op_succinct_mock"],
        "AGGLAYER": args["op_succinct_agglayer"],  # agglayer/op-succinct specific.
        "GRPC_ADDRESS": "0.0.0.0:"
        + str(args["op_succinct_proposer_grpc_port"]),  # agglayer/op-succinct specific.
        "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
        "MAX_CONCURRENT_PROOF_REQUESTS": args[
            "op_succinct_max_concurrent_proof_requests"
        ],
        "MAX_CONCURRENT_WITNESS_GEN": args["op_succinct_max_concurrent_witness_gen"],
        "RANGE_PROOF_INTERVAL": args["op_succinct_range_proof_interval"],
        "DATABASE_URL": "postgres://op_succinct_user:op_succinct_password@postgres"
        + args["deployment_suffix"]
        + ":5432/op_succinct_db",
        "PROVER_ADDRESS": args["zkevm_l2_sequencer_address"],
        "METRICS_PORT": str(args["op_succinct_proposer_metrics_port"]),
        # "DGF_ADDRESS": "", # Address of the DisputeGameFactory contract. Note: If set, the proposer will create a dispute game with the DisputeGameFactory, rather than the OPSuccinctL2OutputOracle. Compatible with OptimismPortal2.
        # "LOOP_INTERVAL": 60, # Default: 60. The interval (in seconds) between each iteration of the OP Succinct service.
        # "SAFE_DB_FALLBACK": False, # Default: false. Whether to fallback to timestamp-based L1 head estimation even though SafeDB is not activated for op-node. When false, proposer will panic if SafeDB is not available. It is by default false since using the fallback mechanism will result in higher proving cost.
        # "SIGNER_URL": "", # URL for the Web3Signer. Note: This takes precedence over the `PRIVATE_KEY` environment variable.
        # "SIGNER_ADDRESS": "", # Address of the account that will be posting output roots to L1. Note: Only set this if the signer is a Web3Signer. Note: Required if `SIGNER_URL` is set.
        # Kurtosis CDK specific - required to see logs in the op-succinct-proposer after https://github.com/agglayer/op-succinct/commit/892085405a65a2b1c245beca3dcb9d9f5626af0e commit
        # Kurtosis CDK specific - https://github.com/agglayer/op-succinct/commit/cffd968bd744cddc262543e1195fdd36110ecf83
        "RUST_LOG": args.get("log_level"),
        "LOG_FORMAT": args.get("log_format"),
    }

    op_succinct_proposer_service_config = ServiceConfig(
        image=args["op_succinct_proposer_image"],
        ports=ports,
        env_vars=env_vars,
        files={
            "/app/configs/L1": Directory(artifact_names=[l1_genesis_artifact]),
        },
    )
    return {op_succinct_name: op_succinct_proposer_service_config}


def get_op_succinct_proposer_ports(args):
    ports = {
        "prometheus": PortSpec(
            args["op_succinct_proposer_metrics_port"],
            application_protocol="http",
            wait="60s",
        ),
        "grpc": PortSpec(
            args["op_succinct_proposer_grpc_port"],
            application_protocol="grpc",
            wait="60s",
        ),
    }

    return ports
