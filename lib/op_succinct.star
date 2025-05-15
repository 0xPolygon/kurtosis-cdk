ARTIFACTS = [
    {
        "name": "deploy-op-succinct-contracts.sh",
        "file": "../templates/op-succinct/deploy-op-succinct-contracts.sh",
    },
]


# The VERIFIER_ADDRESS, L2OO_ADDRESS will need to be dynamically parsed from the output of the contract deployer
# NETWORK_PRIVATE_KEY must be from user input
def create_op_succinct_proposer_service_config(
    plan,
    args,
    db_artifact,
):
    artifact_paths = list(ARTIFACTS)
    artifacts = []
    for artifact_cfg in artifact_paths:
        template = read_file(src=artifact_cfg["file"])
        artifact = plan.render_templates(
            name=artifact_cfg["name"],
            config={artifact_cfg["name"]: struct(template=template, data=args)},
        )
        artifacts.append(artifact)

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
        "VERIFIER_ADDRESS": "0xf22E2B040B639180557745F47aB97dFA95B1e22a",  # TODO fix this to be dynamic
        "AGG_PROOF_MODE": args["op_succinct_agg_proof_mode"],
        "L2OO_ADDRESS": "0x414e9E227e4b589aF92200508aF5399576530E4e",  # TODO fix this to be dynamic
        "OP_SUCCINCT_MOCK": str(
            args["op_succinct_mock"]
        ).lower(),  # TODO this should be a boolean
        "AGGLAYER": str(
            args["op_succinct_agglayer"]
        ).lower(),  # agglayer/op-succinct specific. TODO this should be a boolean
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
    }

    op_succinct_proposer_service_config = ServiceConfig(
        image=args["op_succinct_proposer_image"],
        ports=ports,
        files={
            "/opt/scripts/": Directory(
                artifact_names=[
                    artifacts[0],
                ],
            ),
            "/usr/local/bin/dbdata/"
            + str(args["zkevm_rollup_chain_id"]): Directory(
                artifact_names=[
                    db_artifact,
                ],
            ),
        },
        env_vars=env_vars,
    )

    return {op_succinct_name: op_succinct_proposer_service_config}


def get_op_succinct_proposer_ports(args):
    # TODO "wait=None" is a hack to bypass the port checks.
    # The ports will need to be opened, but will only be used later on when the validity-proposer binary runs.
    ports = {
        "prometheus": PortSpec(
            args["op_succinct_proposer_metrics_port"],
            application_protocol="http",
            wait=None,
        ),
        "grpc": PortSpec(
            args["op_succinct_proposer_grpc_port"],
            application_protocol="grpc",
            wait=None,
        ),
    }

    return ports
