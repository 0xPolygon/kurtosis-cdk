ARTIFACTS = [
    {
        "name": "deploy-op-succinct-contracts.sh",
        "file": "../templates/op-succinct/deploy-op-succinct-contracts.sh",
    },
]

def create_op_succinct_contract_deployer_service_config(
    plan, args,
):
    artifact_paths = list(ARTIFACTS)
    artifacts = []
    for artifact_cfg in artifact_paths:
        template = read_file(src=artifact_cfg["file"])
        artifact = plan.render_templates(
            name=artifact_cfg["name"],
            config={
                artifact_cfg["name"]: struct(
                    template=template,
                    data=args
                )
            },
        )
        artifacts.append(artifact)

    op_succinct_name = "op-succinct-contract-deployer" + args["deployment_suffix"]
    op_succinct_contract_deployer_service_config = ServiceConfig(
        image=args["op_succinct_contract_deployer_image"],
        files={
            "/opt/scripts/": Directory(
                artifact_names=[
                    artifacts[0],
                ],
            ),
        },
    )

    return {op_succinct_name: op_succinct_contract_deployer_service_config}

def create_op_succinct_server_service_config(
    args,
):
    op_succinct_name = "op-succinct-server" + args["deployment_suffix"]
    ports = get_op_succinct_server_ports(args)
    op_succinct_server_service_config = ServiceConfig(
        image=args["op_succinct_server_image"],
        ports=ports,
        env_vars = {
        "L1_RPC":"http://el-1-geth-lighthouse:8545",
        "L1_BEACON_RPC":"http://cl-1-lighthouse-geth:4000",
        "L2_RPC":"http://op-el-1-op-geth-op-node-op-kurtosis:8545",
        "L2_NODE_RPC":"http://op-cl-1-op-node-op-geth-op-kurtosis:8547",
        "PRIVATE_KEY":"bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31",
        "ETHERSCAN_API_KEY":"",
        "VERIFIER_ADDRESS":"0x48b90E15Bd620e44266CCbba434C3f454a12b361",
        "L2OO_ADDRESS":"0x0EeC8BC5B2A3879A9B8997100486F4e26a4f299f",
        "OP_SUCCINCT_MOCK":"true",
        },
    )

    return {op_succinct_name: op_succinct_server_service_config}


def create_op_succinct_proposer_service_config(
    args,
    db_artifact,
):
    op_succinct_name = "op-succinct-proposer" + args["deployment_suffix"]
    ports = get_op_succinct_proposer_ports(args)
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
        env_vars = {
        "L1_RPC":"http://el-1-geth-lighthouse:8545",
        "L1_BEACON_RPC":"http://cl-1-lighthouse-geth:4000",
        "L2_RPC":"http://op-el-1-op-geth-op-node-op-kurtosis:8545",
        "L2_NODE_RPC":"http://op-cl-1-op-node-op-geth-op-kurtosis:8547",
        "PRIVATE_KEY":"bcdf20249abf0ed6d944c0288fad489e33f66b3960d9e6229c1cd214ed3bbe31",
        "ETHERSCAN_API_KEY":"",
        "VERIFIER_ADDRESS":"0x48b90E15Bd620e44266CCbba434C3f454a12b361",
        "L2OO_ADDRESS":"0x0EeC8BC5B2A3879A9B8997100486F4e26a4f299f",
        "OP_SUCCINCT_MOCK":"true",
        },
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
            args["op_succinct_proposer_port"],
            application_protocol="http",
            wait=None,
        ),
    }

    return ports

