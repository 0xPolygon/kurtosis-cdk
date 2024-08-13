data_availability_package = import_module("./data_availability.star")

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

    cdk_node_service_config = ServiceConfig(
        image=args["cdk_node_image"],
        ports={
            "aggregator": PortSpec(
                args["zkevm_aggregator_port"], application_protocol="grpc"
            ),
        },
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
            "sleep 20 && cdk-node run "
            + "-cfg=/etc/cdk/cdk-node-config.toml "
            + "-custom-network-file=/etc/cdk/genesis.json "
            + "-components="
            + NODE_COMPONENTS.sequence_sender
            + ","
            + NODE_COMPONENTS.aggregator,
        ],
    )

    return {cdk_node_name: cdk_node_service_config}
