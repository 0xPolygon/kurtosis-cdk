constants = import_module("../src/package_io/constants.star")
ports_package = import_module("../src/package_io/ports.star")

AGGKIT_BINARY_NAME = "aggkit"


def create_cdk_node_service_config(
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
):
    cdk_node_name = "cdk-node" + args["deployment_suffix"]
    (ports, public_ports) = get_cdk_node_ports(args)
    service_command = get_cdk_node_cmd(args)
    cdk_node_service_config = ServiceConfig(
        image=args["cdk_node_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/cdk": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    keystore_artifact.aggregator,
                    keystore_artifact.sequencer,
                    keystore_artifact.claim_sponsor,
                ],
            ),
            "/data": Directory(
                artifact_names=[],
            ),
        },
        entrypoint=["sh", "-c"],
        cmd=service_command,
    )

    return {cdk_node_name: cdk_node_service_config}


def get_cdk_node_ports(args):
    # We won't have an aggregator if we're in PP mode
    if args["consensus_contract_type"] == constants.CONSENSUS_TYPE.pessimistic:
        ports = {
            "rpc": PortSpec(
                args.get("cdk_node_rpc_port"),
                application_protocol="http",
                wait=None,
            ),
            "rest": PortSpec(
                args.get("aggkit_node_rest_api_port"),
                application_protocol="http",
                wait=None,
            ),
        }
        public_ports = ports_package.get_public_ports(
            ports, "cdk_node_start_port", args
        )
        return (ports, public_ports)

    # In the case where we have pre deployed contract, the cdk node
    # can go through a syncing process that takes a long time and
    # might exceed the start up time
    aggregator_wait = "2m"
    if (
        "use_previously_deployed_contracts" in args
        and args["use_previously_deployed_contracts"]
    ):
        aggregator_wait = None

    # FEP requires the aggregator
    ports = {
        "rpc": PortSpec(
            args.get("cdk_node_rpc_port"),
            application_protocol="http",
            wait=None,
        ),
        "rest": PortSpec(
            args.get("aggkit_node_rest_api_port"),
            application_protocol="http",
            wait=None,
        ),
    }

    # Non-pessimistic rollups require an aggregator.
    if args.get("consensus_contract_type") != constants.CONSENSUS_TYPE.pessimistic:
        # Determine the wait time for the aggregator.
        # If using pre-deployed contracts, the cdk node can go through a syncing process
        # that takes a long time and might exceed the start up time.
        aggregator_wait = "2m"
        if args.get("use_previously_deployed_contracts"):
            aggregator_wait = None

        ports["aggregator"] = PortSpec(
            args.get("zkevm_aggregator_port"),
            application_protocol="grpc",
            wait=aggregator_wait,
        )

    public_ports = ports_package.get_public_ports(ports, "cdk_node_start_port", args)
    return (ports, public_ports)


def get_cdk_node_cmd(args):
    binary_name = args.get("binary_name")

    service_command = [
        "sleep 20 && cdk-node run "
        + "--cfg=/etc/cdk/cdk-node-config.toml "
        + "--custom-network-file=/etc/cdk/genesis.json "
        + "--components=sequence-sender,aggregator"
    ]

    if args["consensus_contract_type"] == constants.CONSENSUS_TYPE.pessimistic:
        service_command = [
            "sleep 20 && cdk-node run "
            + "--cfg=/etc/cdk/cdk-node-config.toml "
            + "--custom-network-file=/etc/cdk/genesis.json "
            + "--save-config-path=/tmp "
            + "--components=aggsender"
        ]

    if binary_name == AGGKIT_BINARY_NAME:
        service_command = [
            "sleep 20 && aggkit run "
            + "--cfg=/etc/cdk/cdk-node-config.toml "
            + "--save-config-path=/tmp "
            + "--components=aggsender,bridge"
        ]

    return service_command
