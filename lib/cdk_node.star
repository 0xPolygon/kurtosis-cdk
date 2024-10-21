data_availability_package = import_module("./data_availability.star")

NODE_COMPONENTS = struct(
    sequence_sender="sequence-sender",
    aggregator="aggregator",
    aggsender="aggsender",
)


def create_cdk_node_service_config(
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
):
    cdk_node_name = "cdk-node" + args["deployment_suffix"]

    cdk_ports = dict()

    cdk_ports["aggregator"] = PortSpec(
        args["zkevm_aggregator_port"], application_protocol="grpc"
    )

    service_command = [
        "sleep 20 && cdk-node run "
        + "--config=/etc/cdk/cdk-node-config.toml "
        + "--custom-network-file=/etc/cdk/genesis.json "
        + "--components="
        + NODE_COMPONENTS.sequence_sender
        + ","
        + NODE_COMPONENTS.aggregator,
    ]

    if args["consensus_contract_type"] == "pessimistic":
        cdk_ports = dict()
        service_command = [
            "sleep 20 && cdk-node run "
            + "--config=/etc/cdk/cdk-node-config.toml "
            + "--custom-network-file=/etc/cdk/genesis.json "
            + "--components=rpc,"
            + NODE_COMPONENTS.aggsender
        ]

    cdk_node_service_config = ServiceConfig(
        image=args["cdk_node_image"],
        ports=cdk_ports,
        files={
            "/etc/cdk": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    keystore_artifact.aggregator,
                    keystore_artifact.sequencer,
                    keystore_artifact.claimsponsor,
                ],
            ),
            "/data": Directory(
                artifact_names=[],
            ),
        },
        entrypoint=["sh", "-c"],
        # Sleep for 20 seconds in order to wait for datastream server getting ready
        # TODO: find a better way instead of waiting
        cmd=service_command,
    )

    return {cdk_node_name: cdk_node_service_config}
