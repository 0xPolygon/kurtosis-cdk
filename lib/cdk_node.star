data_availability_package = import_module("./data_availability.star")
ports_package = import_module("../src/package_io/ports.star")

NODE_COMPONENTS = struct(
    sequence_sender="sequence-sender",
    aggregator="aggregator",
)


def create_cdk_node_service_config(
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
):
    cdk_node_name = "cdk-node" + args["deployment_suffix"]
    (ports, public_ports) = get_cdk_node_ports(args)
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
                ],
            ),
            "/data": Directory(
                artifact_names=[],
            ),
        },
        entrypoint=["sh", "-c"],
        # Sleep for 20 seconds in order to wait for datastream server getting ready
        # TODO: find a better way instead of waiting
        cmd=[
            "sleep 20 && cdk "
            + "node "
            + "--config=/etc/cdk/cdk-node-config.toml "
            + "--components="
            + NODE_COMPONENTS.sequence_sender
            + ","
            + NODE_COMPONENTS.aggregator,
        ],
    )

    return {cdk_node_name: cdk_node_service_config}


def get_cdk_node_ports(args):
    ports = {
        "aggregator": PortSpec(
            args["zkevm_aggregator_port"], application_protocol="grpc"
        ),
    }
    public_ports = ports_package.get_public_ports(ports, "agglayer_start_port", args)
    return (ports, public_ports)
