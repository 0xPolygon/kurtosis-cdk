ARTIFACTS = [
    {
        "name": "deploy-op-succinct-contracts.sh",
        "file": "../templates/op-succinct/deploy-op-succinct-contracts.sh",
    },
    {
        "name": "deploy-l2oo.sh",
        "file": "../templates/op-succinct/deploy-l2oo.sh",
    },
]


def create_op_succinct_contract_deployer_service_config(
    plan,
    args,
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

    op_succinct_name = "op-succinct-contract-deployer" + args["deployment_suffix"]
    op_succinct_contract_deployer_service_config = ServiceConfig(
        image=args["op_succinct_contract_deployer_image"],
        files={
            "/opt/scripts/": Directory(
                artifact_names=[
                    artifacts[0],
                    artifacts[1],
                ],
            ),
        },
    )

    return {op_succinct_name: op_succinct_contract_deployer_service_config}


# curl -s --json '{"address":"0x414e9E227e4b589aF92200508aF5399576530E4e"}' $(kurtosis port print aggkit op-succinct-server-001 server)/validate_config | jq '.'


# The VERIFIER_ADDRESS, L2OO_ADDRESS will need to be dynamically parsed from the output of the contract deployer
# NETWORK_PRIVATE_KEY must be from user input
def create_op_succinct_proposer_service_config(
    args,
    op_succinct_env_vars,
    db_artifact,
):
    op_succinct_name = "op-succinct-proposer" + args["deployment_suffix"]
    ports = get_op_succinct_proposer_ports(args)

    # If we are using the network prover, we use the real verifier address
    if op_succinct_env_vars["op_succinct_mock"] == False:
        env_vars = {
            "L1_RPC": args["l1_rpc_url"],
            "L1_BEACON_RPC": args["l1_beacon_url"],
            "L2_RPC": args["op_el_rpc_url"],
            "L2_NODE_RPC": args["op_cl_rpc_url"],
            "PRIVATE_KEY": args["l1_preallocated_private_key"],
            "ETHERSCAN_API_KEY": "",
            "VERIFIER_ADDRESS": args["agglayer_gateway_address"],
            # "L2OO_ADDRESS": op_succinct_env_vars["l2oo_address"],
            "L2OO_ADDRESS": args["zkevm_rollup_address"],
            "OP_SUCCINCT_MOCK": op_succinct_env_vars["op_succinct_mock"],
            "AGGLAYER": op_succinct_env_vars["op_succinct_agglayer"],
            "GRPC_ADDRESS": "[::]:50051",
            "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
            "MAX_BLOCK_RANGE_PER_SPAN_PROOF": args["op_succinct_proposer_span_proof"],
            "MAX_CONCURRENT_PROOF_REQUESTS": args[
                "op_succinct_max_concurrent_proof_requests"
            ],
            "MAX_CONCURRENT_WITNESS_GEN": args[
                "op_succinct_max_concurrent_witness_gen"
            ],
            "RANGE_PROOF_INTERVAL": args["op_succinct_range_proof_interval"],
            "DATABASE_URL": "postgres://op_succinct_user:op_succinct_password@postgres"
            + args["deployment_suffix"]
            + ":5432/op_succinct_db",
        }
    # For local prover, we use the mock verifier address
    else:
        env_vars = {
            "L1_RPC": args["l1_rpc_url"],
            "L1_BEACON_RPC": args["l1_beacon_url"],
            "L2_RPC": args["op_el_rpc_url"],
            "L2_NODE_RPC": args["op_cl_rpc_url"],
            "PRIVATE_KEY": args["l1_preallocated_private_key"],
            "ETHERSCAN_API_KEY": "",
            # "VERIFIER_ADDRESS": op_succinct_env_vars["mock_verifier_address"],
            "VERIFIER_ADDRESS": args["agglayer_gateway_address"],
            # "L2OO_ADDRESS": op_succinct_env_vars["l2oo_address"],
            "L2OO_ADDRESS": args["zkevm_rollup_address"],
            "OP_SUCCINCT_MOCK": op_succinct_env_vars["op_succinct_mock"],
            "AGGLAYER": op_succinct_env_vars["op_succinct_agglayer"],
            "GRPC_ADDRESS": "[::]:50051",
            "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
            "MAX_BLOCK_RANGE_PER_SPAN_PROOF": args["op_succinct_proposer_span_proof"],
            "MAX_CONCURRENT_PROOF_REQUESTS": args[
                "op_succinct_max_concurrent_proof_requests"
            ],
            "MAX_CONCURRENT_WITNESS_GEN": args[
                "op_succinct_max_concurrent_witness_gen"
            ],
            "RANGE_PROOF_INTERVAL": args["op_succinct_range_proof_interval"],
            "DATABASE_URL": "postgres://op_succinct_user:op_succinct_password@postgres"
            + args["deployment_suffix"]
            + ":5432/op_succinct_db",
        }

    op_succinct_proposer_service_config = ServiceConfig(
        image=args["op_succinct_proposer_image"],
        ports=ports,
        files={
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
    ports = {
        "metrics": PortSpec(
            args["op_succinct_proposer_metrics_port"],
            application_protocol="http",
            wait=None,
        ),
        "grpc": PortSpec(
            args["op_succinct_proposer_grpc_port"],
            application_protocol="http",
            wait=None,
        ),
    }

    return ports
