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
    (ports, public_ports) = get_aggkit_ports(args, None)
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
            "/tmp": Directory(persistent_key="aggkit-tmp" + args["deployment_suffix"]),
        },
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=service_command,
    )

    configs_to_return = {aggkit_name: aggkit_cdk_service_config}

    return configs_to_return


def create_root_aggkit_service_config(
    plan,
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
    member_index=0,
):
    # Check if claim sponsor is enabled and "bridge" is not in aggkit_components
    log_claim_sponsor_warning(plan, args)

    # Build components list
    components = args.get("aggkit_components", "")

    aggkit_name = "aggkit" + args["deployment_suffix"]
    selected_keystore = keystore_artifact.aggoracle

    (ports, public_ports) = get_aggkit_ports(args, None)
    service_command = get_aggkit_cmd(args)

    root_aggkit_service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/aggkit": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    selected_keystore,
                    keystore_artifact.sovereignadmin,
                    keystore_artifact.claimtx,
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

    configs_to_return = {aggkit_name: root_aggkit_service_config}
    return configs_to_return


def create_aggkit_bridge_service_config(
    plan,
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
    member_index=0,
):
    # Check if claim sponsor is enabled and "bridge" is not in aggkit_components
    log_claim_sponsor_warning(plan, args)

    aggkit_name = "aggkit" + args["deployment_suffix"] + "-bridge"
    selected_keystore = keystore_artifact.aggoracle

    (ports, public_ports) = get_aggkit_ports(args, None)
    # Only run bridge component for committee members
    service_command = [
        "run",
        "--cfg=/etc/aggkit/config.toml",
        "--components=bridge",
    ]

    aggkit_bridge_service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/aggkit": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    selected_keystore,
                    keystore_artifact.sovereignadmin,
                    keystore_artifact.claimtx,
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

    configs_to_return = {aggkit_name: aggkit_bridge_service_config}
    return configs_to_return


def create_aggoracle_service_config(
    plan,
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
    member_index=0,
):
    """Creates aggoracle-only service configs for committee members > 0"""

    if member_index == 0:
        # Skip member_index 0 as it's handled by root service
        return {}

    # Check if claim sponsor is enabled and "bridge" is not in aggkit_components
    log_claim_sponsor_warning(plan, args)

    # Committee member naming
    aggkit_name = (
        "aggkit"
        + args["deployment_suffix"]
        + "-aggoracle-committee-00"
        + str(member_index)
    )

    # Use committee-specific keystore
    selected_keystore = (
        keystore_artifact.committee_keystores[member_index]
        if member_index < len(keystore_artifact.committee_keystores)
        else keystore_artifact.aggoracle
    )

    (ports, public_ports) = get_aggkit_ports(args, None)

    # Only run aggoracle component for committee members
    service_command = [
        "run",
        "--cfg=/etc/aggkit/config.toml",
        "--components=aggoracle",
    ]

    aggoracle_service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/aggkit": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    selected_keystore,
                    keystore_artifact.sovereignadmin,
                    keystore_artifact.claimtx,
                    keystore_artifact.sequencer,
                ],
            ),
            "/data": Directory(
                artifact_names=[],
            ),
            "/tmp": Directory(persistent_key="aggkit-tmp" + args["deployment_suffix"]),
        },
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=service_command,
    )

    configs_to_return = {aggkit_name: aggoracle_service_config}
    return configs_to_return


def create_aggsender_validator_service_config(
    plan,
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifact,
    member_index=0,
):
    """Creates aggsender-validator service configs"""

    # Check if claim sponsor is enabled and "bridge" is not in aggkit_components
    log_claim_sponsor_warning(plan, args)

    # Aggsender validator naming
    aggkit_name = (
        "aggkit"
        + args["deployment_suffix"]
        + "-aggsender-validator-00"
        + str(member_index)
    )

    # Use aggsender validator keystore
    selected_keystore = keystore_artifact.aggsender_validator_keystores[
        member_index
        - 2  # Convert from 2-based to 0-based indexing when accessing aggsender_validator_keystores array
    ]

    (ports, public_ports) = get_aggkit_ports(args, "aggsender_validator")

    # Only run aggsender-validator component
    service_command = [
        "run",
        "--cfg=/etc/aggkit/config.toml",
        "--components=aggsender-validator",
    ]

    aggsender_validator_service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/aggkit": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    selected_keystore,
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

    configs_to_return = {aggkit_name: aggsender_validator_service_config}
    return configs_to_return


def get_aggkit_ports(args, service_type=None):
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

    # Only add validator-grpc port for aggsender-validator service
    if service_type == "aggsender_validator" and args.get("use_agg_sender_validator"):
        ports["validator-grpc"] = PortSpec(
            args.get("aggsender_validator_grpc_port"),
            application_protocol="grpc",
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
