ports_package = import_module("../src/package_io/ports.star")


def create_cdk_aggoracle_service_config(
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
):
    cdk_aggoracle_name = "cdk-aggoracle" + args["deployment_suffix"]
    (ports, public_ports) = get_cdk_aggoracle_ports(args)
    service_command = get_cdk_aggoracle_cmd(args)
    cdk_aggoracle_service_config = ServiceConfig(
        image=args["cdk_node_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/app": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    keystore_artifact.claimsponsor,
                    keystore_artifact.aggoracle,
                ],
            ),
            "/data": Directory(
                artifact_names=[],
            ),
        },
        entrypoint=["sh", "-c"],
        cmd=service_command,
    )

    return {cdk_aggoracle_name: cdk_aggoracle_service_config}


def get_cdk_aggoracle_ports(args):
    # FEP requires the aggregator
    ports = {
        "rpc": PortSpec(
            args["zkevm_cdk_node_port"],
            application_protocol="http",
            wait=None,
        ),
    }

    public_ports = ports_package.get_public_ports(ports, "cdk_node_start_port", args)
    return (ports, public_ports)


def get_cdk_aggoracle_cmd(args):
    service_command = [
        "sleep 20 && cdk-node run "
        + "--cfg=/app/config.toml "
        + "--custom-network-file=/app/genesis.json "
        + "--components=aggoracle,rpc"
    ]

    return service_command
