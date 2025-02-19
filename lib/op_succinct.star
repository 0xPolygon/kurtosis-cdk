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

    op_succinct_name = "op-succinct-contract-deployer"
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

# The VERIFIER_ADDRESS, L2OO_ADDRESS will need to be dynamically parsed from the output of the contract deployer
# NETWORK_PRIVATE_KEY must be from user input
def create_op_succinct_server_service_config(
    args,
):
    op_succinct_name = "op-succinct-server"
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
        "VERIFIER_ADDRESS":"0xaE37C7A711bcab9B0f8655a97B738d6ccaB6560B",
        "L2OO_ADDRESS":"0x7E2E7DD2Aead92e2e6d05707F21D4C36004f8A2B",
        "OP_SUCCINCT_MOCK":"true",
        "NETWORK_PRIVATE_KEY":args["agglayer_prover_sp1_key"],
        },
    )

    return {op_succinct_name: op_succinct_server_service_config}

# The VERIFIER_ADDRESS, L2OO_ADDRESS will need to be dynamically parsed from the output of the contract deployer
# NETWORK_PRIVATE_KEY must be from user input
def create_op_succinct_proposer_service_config(
    args,
    db_artifact,
):
    op_succinct_name = "op-succinct-proposer"
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
        "VERIFIER_ADDRESS":"0xaE37C7A711bcab9B0f8655a97B738d6ccaB6560B",
        "L2OO_ADDRESS":"0x7E2E7DD2Aead92e2e6d05707F21D4C36004f8A2B",
        "OP_SUCCINCT_MOCK":"true",
        "NETWORK_PRIVATE_KEY":args["agglayer_prover_sp1_key"],
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

