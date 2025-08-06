constants = import_module("../src/package_io/constants.star")
ports_package = import_module("../src/package_io/ports.star")


def log_claim_sponsor_warning(plan, args):
    if args.get("enable_aggkit_claim_sponsor", False):
        components = args.get("aggkit_components", [])
        if "bridge" not in components:
            plan.print(
                "⚠️  WARNING: Claim sponsor is enabled, but 'bridge' is not included in aggkit components — the claim sponsor feature will be disabled."
            )


def create_aggkit_cdk_service_config(
    plan,
    args,
    config_artifact,
    keystore_artifact,
):
    # Check if claim sponsor is enabled and "bridge" is not in aggkit_components
    log_claim_sponsor_warning(plan, args)

    aggkit_name = "aggkit" + args["deployment_suffix"]
    (ports, public_ports) = get_aggkit_ports(args)
    service_command = get_aggkit_cmd(args)
    aggkit_cdk_service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/aggkit": Directory(
                artifact_names=[
                    config_artifact,
                    keystore_artifact.sequencer,
                    keystore_artifact.claim_sponsor,
                ],
            ),
            "/data": Directory(
                artifact_names=[],
            ),
        },
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=service_command,
    )

    configs_to_return = {aggkit_name: aggkit_cdk_service_config}

    return configs_to_return


def create_aggkit_service_config(
    plan,
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
):
    # Check if claim sponsor is enabled and "bridge" is not in aggkit_components
    log_claim_sponsor_warning(plan, args)

    aggkit_name = "aggkit" + args["deployment_suffix"]
    (ports, public_ports) = get_aggkit_ports(args)
    service_command = get_aggkit_cmd(args)
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
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=service_command,
    )

    configs_to_return = {aggkit_name: cdk_aggoracle_service_config}
    if args["use_agg_sender_validator"]:
        svc_name = "aggkit-validator" + args["deployment_suffix"]
        (ports, public_ports) = get_aggkit_ports(args)
        service_command = get_aggkit_cmd(args)
        aggkit_cdk_service_config = ServiceConfig(
            image=args["aggkit_image"],
            ports=ports,
            # public_ports=public_ports,
            files={
                "/etc/aggkit": Directory(
                    artifact_names=[
                        config_artifact,
                        keystore_artifact.claim_sponsor,
                        keystore_artifact.aggkit_validator,
                    ],
                ),
                "/data": Directory(
                    artifact_names=[],
                ),
            },
            entrypoint=["/usr/local/bin/aggkit"],
            cmd=[
                "run",
                "--cfg=/etc/aggkit/config.toml",
                "--components=aggsender-validator",
            ],
        )
        configs_to_return[svc_name] = aggkit_cdk_service_config

    return configs_to_return


def get_aggkit_ports(args):
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

    if args.get("aggkit_pprof_enabled"):
        ports["pprof"] = PortSpec(
            args.get("aggkit_pprof_port"),
            application_protocol="http",
            wait=None,
        )

    public_ports = ports_package.get_public_ports(ports, "cdk_node_start_port", args)
    return (ports, public_ports)


def get_aggkit_cmd(args):
    service_command = [
        "run",
        "--cfg=/etc/aggkit/config.toml",
        "--components=" + args.get("aggkit_components", ""),
    ]
    return service_command
