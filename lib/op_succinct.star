ARTIFACTS = [
    {
        "name": "deploy-op-succinct-contracts.sh",
        "file": "../templates/op-succinct/deploy-op-succinct-contracts.sh",
    },
    {
        "name": "deploy-sp1-verifier-contracts.sh",
        "file": "../templates/op-succinct/deploy-sp1-verifier-contracts.sh",
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
                    artifacts[2],
                ],
            ),
        },
    )

    return {op_succinct_name: op_succinct_contract_deployer_service_config}


# The VERIFIER_ADDRESS, L2OO_ADDRESS will need to be dynamically parsed from the output of the contract deployer
# NETWORK_PRIVATE_KEY must be from user input
def create_op_succinct_server_service_config(
    args,
    op_succinct_env_vars,
):
    op_succinct_name = "op-succinct-server" + args["deployment_suffix"]
    ports = get_op_succinct_server_ports(args)

    # If we are using the network prover, we use the real verifier address
    if op_succinct_env_vars["op_succinct_mock"] == False:
        env_vars = {
            "L1_RPC": args["l1_rpc_url"],
            "L1_BEACON_RPC": args["l1_beacon_url"],
            "L2_RPC": args["op_el_rpc_url"],
            "L2_NODE_RPC": args["op_cl_rpc_url"],
            "PRIVATE_KEY": args["l1_preallocated_private_key"],
            "ETHERSCAN_API_KEY": "",
            # "VERIFIER_ADDRESS": op_succinct_env_vars["sp1_verifier_gateway_address"],
            # "L2OO_ADDRESS": op_succinct_env_vars["l2oo_address"],
            "OP_SUCCINCT_MOCK": op_succinct_env_vars["op_succinct_mock"],
            "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
            "NETWORK_RPC_URL": args["agglayer_prover_network_url"],
            "AGG_PROOF_MODE": op_succinct_env_vars["op_succinct_agg_proof_mode"],
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
            # "L2OO_ADDRESS": op_succinct_env_vars["l2oo_address"],
            "OP_SUCCINCT_MOCK": op_succinct_env_vars["op_succinct_mock"],
            "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
            "NETWORK_RPC_URL": args["agglayer_prover_network_url"],
            "AGG_PROOF_MODE": op_succinct_env_vars["op_succinct_agg_proof_mode"],
        }

    op_succinct_server_service_config = ServiceConfig(
        image=args["op_succinct_server_image"],
        ports=ports,
        env_vars=env_vars,
    )

    return {op_succinct_name: op_succinct_server_service_config}


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
            "OP_SUCCINCT_AGGLAYER": op_succinct_env_vars["op_succinct_agglayer"],
            "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
            "MAX_BLOCK_RANGE_PER_SPAN_PROOF": args["op_succinct_proposer_span_proof"],
            "MAX_CONCURRENT_PROOF_REQUESTS": args[
                "op_succinct_max_concurrent_proof_requests"
            ],
            "MAX_CONCURRENT_WITNESS_GEN": args[
                "op_succinct_max_concurrent_witness_gen"
            ],
            "OP_SUCCINCT_SERVER_URL": "http://op-succinct-server"
            + args["deployment_suffix"]
            + ":"
            + str(args["op_succinct_server_port"]),
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
            "OP_SUCCINCT_AGGLAYER": op_succinct_env_vars["op_succinct_agglayer"],
            "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
            "MAX_BLOCK_RANGE_PER_SPAN_PROOF": args["op_succinct_proposer_span_proof"],
            "MAX_CONCURRENT_PROOF_REQUESTS": args[
                "op_succinct_max_concurrent_proof_requests"
            ],
            "MAX_CONCURRENT_WITNESS_GEN": args[
                "op_succinct_max_concurrent_witness_gen"
            ],
            "OP_SUCCINCT_SERVER_URL": "http://op-succinct-server"
            + args["deployment_suffix"]
            + ":"
            + str(args["op_succinct_server_port"]),
        }

    op_succinct_proposer_service_config = ServiceConfig(
        image=args["op_succinct_proposer_image"],
        ports=ports,
        files={
            "/usr/local/bin/dbdata/2151908": Directory(
                artifact_names=[
                    db_artifact,
                ],
            ),
        },
        env_vars=env_vars,
    )

    return {op_succinct_name: op_succinct_proposer_service_config}


def get_op_succinct_server_ports(args):
    ports = {
        "server": PortSpec(
            args["op_succinct_server_port"],
            application_protocol="http",
            wait=None,
        ),
    }

    return ports


def get_op_succinct_proposer_ports(args):
    ports = {
        "metrics": PortSpec(
            args["op_succinct_proposer_metrics_port"],
            application_protocol="http",
            wait=None,
        ),
        "rpc": PortSpec(
            args["op_succinct_proposer_rpc_port"],
            application_protocol="http",
            wait=None,
        ),
    }

    return ports
