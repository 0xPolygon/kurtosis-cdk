constants = import_module("../src/package_io/constants.star")
ports_package = import_module("../src/package_io/ports.star")


def create_aggkit_service_config(
    args,
    deployment_stages,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
):
    aggkit_name = "aggkit" + args["deployment_suffix"]
    (ports, public_ports) = get_aggkit_ports(args)
    service_command = get_aggkit_cmd(args, deployment_stages)
    cdk_aggoracle_service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/aggkit": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    keystore_artifact.aggoracle,
                    keystore_artifact.sovereignadmin,
                    keystore_artifact.claimtx,
                    keystore_artifact.sequencer,
                ],
            ),
            "/data": Directory(
                artifact_names=[],
            ),
        },
        entrypoint=["sh", "-c"],
        cmd=service_command,
    )

    return {aggkit_name: cdk_aggoracle_service_config}


def get_aggkit_ports(args):
    ports = {
        "rpc": PortSpec(
            args.get("zkevm_cdk_node_port"),
            application_protocol="http",
            wait=None,
        ),
    }

    if args.get("aggkit_pprof_enabled"):
        ports["pprof"] = PortSpec(
            args.get("aggkit_pprof_port"),
            application_protocol="http",
            wait=None,
        )

    public_ports = ports_package.get_public_ports(ports, "cdk_node_start_port", args)
    return (ports, public_ports)


def get_aggkit_cmd(args, deployment_stages):
    # If running CDK-Erigon-PP, do not run the aggoracle component.
    if (
        not deployment_stages.get("deploy_optimism_rollup", False)
        and args["consensus_contract_type"] == constants.CONSENSUS_TYPE.pessimistic
    ):
        service_command = [
            "cat /etc/aggkit/config.toml && sleep 20 && aggkit run "
            + "--cfg=/etc/aggkit/config.toml "
            + "--components=aggsender"
        ]
    else:
        service_command = [
            "cat /etc/aggkit/config.toml && sleep 20 && aggkit run "
            + "--cfg=/etc/aggkit/config.toml "
            + "--components=aggsender,aggoracle,bridge"
        ]
    return service_command
