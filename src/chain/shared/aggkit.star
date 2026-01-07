aggkit_prover = import_module("./aggkit_prover.star")
constants = import_module("../../package_io/constants.star")
databases = import_module("../shared/databases.star")
ports_package = import_module("./ports.star")
contracts_util = import_module("../../contracts/util.star")
op_succinct = import_module("../op-geth/op_succinct_proposer.star")


def run_aggkit_cdk_node(plan, args, contract_setup_addresses):
    """Deploy aggkit CDK node with inline config creation."""
    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    # Create config artifact
    config_template = read_file(src="../../../static_files/aggkit/cdk-config.toml")
    l2_rpc_url = "http://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.HTTP_RPC_PORT_NUMBER,
    )
    config_artifact = plan.render_templates(
        name="aggkit-cdk-config{}".format(args.get("deployment_suffix")),
        config={
            "config.toml": struct(
                template=config_template,
                data=args
                | db_configs
                | contract_setup_addresses
                | {
                    "l2_rpc_url": l2_rpc_url,
                },
            )
        },
    )

    # Get keystore artifacts
    keystore_artifacts = get_keystores_artifacts(plan, args)

    # Create and deploy service
    service_name = "aggkit" + args["deployment_suffix"]
    ports = _get_aggkit_ports(args)

    files_config = {
        "/etc/aggkit": Directory(
            artifact_names=[
                config_artifact,
                keystore_artifacts.sequencer,
            ]
            + (
                [keystore_artifacts.claim_sponsor]
                if keystore_artifacts.claim_sponsor
                else []
            ),
        ),
        "/data": Directory(persistent_key="aggkit-data" + args["deployment_suffix"]),
        "/tmp": Directory(persistent_key="aggkit-tmp" + args["deployment_suffix"]),
    }

    service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        files=files_config,
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=[
            "run",
            "--cfg=/etc/aggkit/config.toml",
            "--components=" + args.get("aggkit_components", ""),
        ],
    )

    plan.add_service(name=service_name, config=service_config)


def run(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deploy_op_succinct,
):
    """Main orchestration function for deploying aggkit services."""
    # Deploy OP Succinct if needed
    _deploy_op_succinct_if_needed(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deploy_op_succinct,
    )

    # Get common dependencies
    deployment_context = _create_deployment_context(
        plan, args, contract_setup_addresses, sovereign_contract_setup_addresses
    )

    # Deploy core aggkit services
    _deploy_core_aggkit_services(plan, args, deployment_context)

    # Deploy committee members if needed
    _deploy_committee_members_if_needed(plan, args, deployment_context)

    # Deploy validator services if needed
    _deploy_validator_services_if_needed(plan, args, deployment_context)


def _deploy_op_succinct_if_needed(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deploy_op_succinct,
):
    """Deploy OP Succinct if conditions are met."""
    if (
        deploy_op_succinct
        and args["consensus_contract_type"] == constants.CONSENSUS_TYPE.fep
    ):
        aggkit_prover.run(
            plan, args, contract_setup_addresses, sovereign_contract_setup_addresses
        )


def _create_deployment_context(
    plan, args, contract_setup_addresses, sovereign_contract_setup_addresses
):
    """Create common deployment context with shared configurations."""
    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )
    keystore_artifacts = get_keystores_artifacts(plan, args)
    l2_rpc_url = "http://{}{}:{}".format(
        args["l2_rpc_name"],
        args["deployment_suffix"],
        ports_package.HTTP_RPC_PORT_NUMBER,
    )

    # Update sovereign contract addresses with committee address if needed
    updated_sovereign_addresses = _update_sovereign_addresses_with_committee(
        plan, args, sovereign_contract_setup_addresses
    )

    return struct(
        db_configs=db_configs,
        keystore_artifacts=keystore_artifacts,
        l2_rpc_url=l2_rpc_url,
        contract_setup_addresses=contract_setup_addresses,
        sovereign_contract_setup_addresses=updated_sovereign_addresses,
    )


def _deploy_core_aggkit_services(plan, args, deployment_context):
    """Deploy the core aggkit services (main service and bridge)."""
    plan.print("Deploying core aggkit services")

    # Create main aggkit service with inline config
    _deploy_main_aggkit_service(plan, args, deployment_context)

    # Create bridge service with inline config
    _deploy_bridge_service(plan, args, deployment_context)


def _deploy_main_aggkit_service(plan, args, deployment_context):
    """Deploy the main aggkit service with inline config creation."""
    # Create config artifact
    config_template = read_file(src="../../../static_files/aggkit/config.toml")
    config_artifact = plan.render_templates(
        name="aggkit-config{}".format(args.get("deployment_suffix")),
        config={
            "config.toml": struct(
                template=config_template,
                data=_build_config_data(args, deployment_context),
            )
        },
    )

    # Log warning if needed
    _log_claim_sponsor_warning(plan, args)

    # Create and deploy service
    service_name = "aggkit" + args["deployment_suffix"]
    ports = _get_aggkit_ports(args)

    files_config = {
        "/etc/aggkit": Directory(
            artifact_names=[
                config_artifact,
                deployment_context.keystore_artifacts.aggoracle,
                deployment_context.keystore_artifacts.sovereignadmin,
                deployment_context.keystore_artifacts.sequencer,
            ]
            + (
                [deployment_context.keystore_artifacts.claim_sponsor]
                if deployment_context.keystore_artifacts.claim_sponsor
                else []
            ),
        ),
        "/data": Directory(persistent_key="aggkit-data" + args["deployment_suffix"]),
        "/tmp": Directory(persistent_key="aggkit-tmp" + args["deployment_suffix"]),
    }

    service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        files=files_config,
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=[
            "run",
            "--cfg=/etc/aggkit/config.toml",
            "--components=" + args.get("aggkit_components", ""),
        ],
    )

    plan.add_service(name=service_name, config=service_config)


def _deploy_bridge_service(plan, args, deployment_context):
    """Deploy the bridge service with inline config creation."""
    # Create config artifact
    config_template = read_file(src="../../../static_files/aggkit/config.toml")
    config_artifact = plan.render_templates(
        name="aggkit-bridge-config{}".format(args.get("deployment_suffix")),
        config={
            "config.toml": struct(
                template=config_template,
                data=_build_config_data(args, deployment_context),
            )
        },
    )

    # Create and deploy bridge service
    service_name = "aggkit" + args["deployment_suffix"] + "-bridge"
    ports = _get_aggkit_bridge_ports(args)

    files_config = {
        "/etc/aggkit": Directory(
            artifact_names=[
                config_artifact,
                deployment_context.keystore_artifacts.aggoracle,
                deployment_context.keystore_artifacts.sovereignadmin,
                deployment_context.keystore_artifacts.sequencer,
            ]
            + (
                [deployment_context.keystore_artifacts.claim_sponsor]
                if deployment_context.keystore_artifacts.claim_sponsor
                else []
            ),
        ),
        "/data": Directory(artifact_names=[]),
    }

    service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        files=files_config,
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=[
            "run",
            "--cfg=/etc/aggkit/config.toml",
            "--components=bridge",
        ],
    )

    plan.add_service(name=service_name, config=service_config)


def _deploy_committee_members_if_needed(plan, args, deployment_context):
    """Deploy additional oracle committee members if configured."""
    if not _should_deploy_multiple_committee_members(args):
        return

    plan.print("Deploying aggkit committee members")
    total_members = args.get("agg_oracle_committee_total_members", 1)

    for member_index in range(total_members):
        if member_index == 0:
            # Skip member_index 0 as it's handled by main service
            continue

        _deploy_committee_member(plan, args, deployment_context, member_index)


def _deploy_committee_member(plan, args, deployment_context, member_index):
    """Deploy a single committee member with inline config creation."""
    # Create config artifact
    config_template = read_file(src="../../../static_files/aggkit/config.toml")
    config_data = _build_config_data(
        args, deployment_context, {"agg_oracle_committee_member_index": member_index}
    )

    config_artifact = plan.render_templates(
        name="aggkit-aggoracle-config-{}{}".format(
            member_index, args.get("deployment_suffix")
        ),
        config={
            "config.toml": struct(
                template=config_template,
                data=config_data,
            )
        },
    )

    # Use committee-specific keystore
    selected_keystore = (
        deployment_context.keystore_artifacts.committee_keystores[member_index]
        if member_index < len(deployment_context.keystore_artifacts.committee_keystores)
        else deployment_context.keystore_artifacts.aggoracle
    )

    # Create and deploy committee member service
    service_name = (
        "aggkit"
        + args["deployment_suffix"]
        + "-aggoracle-committee-00{}".format(member_index)
    )
    ports = _get_aggkit_ports(args)

    service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        files={
            "/etc/aggkit": Directory(
                artifact_names=[
                    config_artifact,
                    selected_keystore,
                    deployment_context.keystore_artifacts.sovereignadmin,
                    deployment_context.keystore_artifacts.sequencer,
                ],
            ),
            "/data": Directory(artifact_names=[]),
            "/tmp": Directory(
                persistent_key="aggkit-tmp"
                + args["deployment_suffix"]
                + "-aggoracle-committee-00{}".format(member_index)
            ),
        },
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=[
            "run",
            "--cfg=/etc/aggkit/config.toml",
            "--components=aggoracle",
        ],
    )

    plan.add_service(name=service_name, config=service_config)


def _deploy_validator_services_if_needed(plan, args, deployment_context):
    """Deploy aggsender validator services if configured."""
    if not _should_deploy_validator_services(args):
        return

    plan.print("Deploying aggsender validators")
    total_validators = args.get("agg_sender_validator_total_number", 1)

    for validator_index in range(2, total_validators + 1):
        _deploy_validator_service(plan, args, deployment_context, validator_index)


def _deploy_validator_service(plan, args, deployment_context, validator_index):
    """Deploy a single validator service with inline config creation."""
    # Create config artifact
    config_template = read_file(src="../../../static_files/aggkit/config.toml")
    config_data = _build_config_data(
        args, deployment_context, {"agg_sender_validator_member_index": validator_index}
    )

    config_artifact = plan.render_templates(
        name="aggkit-aggsender-config-{}{}".format(
            validator_index, args.get("deployment_suffix")
        ),
        config={
            "config.toml": struct(
                template=config_template,
                data=config_data,
            )
        },
    )

    # Use aggsender validator keystore (convert from 2-based to 0-based indexing)
    selected_keystore = (
        deployment_context.keystore_artifacts.aggsender_validator_keystores[
            validator_index - 2
        ]
    )

    # Create and deploy validator service
    service_name = (
        "aggkit"
        + args["deployment_suffix"]
        + "-aggsender-validator-00{}".format(validator_index)
    )
    ports = _get_aggkit_validator_ports(args)

    service_config = ServiceConfig(
        image=args["aggkit_image"],
        ports=ports,
        files={
            "/etc/aggkit": Directory(
                artifact_names=[
                    config_artifact,
                    selected_keystore,
                    deployment_context.keystore_artifacts.sovereignadmin,
                    deployment_context.keystore_artifacts.sequencer,
                ],
            ),
            "/data": Directory(artifact_names=[]),
        },
        entrypoint=["/usr/local/bin/aggkit"],
        cmd=[
            "run",
            "--cfg=/etc/aggkit/config.toml",
            "--components=aggsender-validator",
        ],
    )

    plan.add_service(name=service_name, config=service_config)


def _update_sovereign_addresses_with_committee(
    plan, args, sovereign_contract_setup_addresses
):
    """Update sovereign contract addresses with committee address if oracle committee is used."""
    if _should_deploy_oracle_committee(args):
        aggoracle_committee_address = contracts_util.get_aggoracle_committee_address(
            plan, args
        )
        return sovereign_contract_setup_addresses | aggoracle_committee_address
    return sovereign_contract_setup_addresses


def _build_config_data(args, deployment_context, extra_data=None):
    """Build configuration data for aggkit services."""
    agglayer_endpoint = _get_agglayer_endpoint(args.get("aggkit_image"))
    aggkit_version = _extract_aggkit_version(args.get("aggkit_image"))

    config_data = (
        args
        | {
            "agglayer_endpoint": agglayer_endpoint,
            "aggkit_version": aggkit_version,
            "l2_rpc_url": deployment_context.l2_rpc_url,
            "aggkit_prover_grpc_port_number": aggkit_prover.GRPC_PORT_NUMBER,
        }
        | deployment_context.db_configs
        | deployment_context.contract_setup_addresses
        | deployment_context.sovereign_contract_setup_addresses
    )

    if extra_data:
        config_data = config_data | extra_data

    return config_data


def _log_claim_sponsor_warning(plan, args):
    """Log warning if claim sponsor is enabled without bridge component."""
    if args.get("enable_aggkit_claim_sponsor", False):
        components = args.get("aggkit_components", [])
        if "bridge" not in components:
            plan.print(
                "⚠️  WARNING: Claim sponsor is enabled, but 'bridge' is not included in aggkit components — the claim sponsor feature will be disabled."
            )


def _get_aggkit_ports(args):
    """Get standard port configuration for aggkit services."""
    return {
        "rpc": PortSpec(
            args.get("cdk_node_rpc_port"),
            application_protocol="http",
            wait=None,
        ),
        "pprof": PortSpec(
            args.get("aggkit_pprof_port"),
            application_protocol="http",
            wait=None,
        ),
    }


def _get_aggkit_bridge_ports(args):
    """Get port configuration for aggkit bridge services."""
    ports = _get_aggkit_ports(args)
    ports["rest"] = PortSpec(
        args.get("aggkit_node_rest_api_port"),
        application_protocol="http",
        wait=None,
    )
    return ports


def _get_aggkit_validator_ports(args):
    """Get port configuration for aggkit validator services."""
    ports = _get_aggkit_ports(args)
    if args.get("use_agg_sender_validator"):
        ports["validator-grpc"] = PortSpec(
            args.get("aggsender_validator_grpc_port"),
            application_protocol="grpc",
            wait=None,
        )
    return ports


def _should_deploy_oracle_committee(args):
    """Check if oracle committee should be deployed."""
    return (
        args.get("use_agg_oracle_committee", False)
        and args.get("agg_oracle_committee_total_members", 0) > 0
        and args.get("agg_oracle_committee_quorum", 0) > 0
    )


def _should_deploy_multiple_committee_members(args):
    """Check if multiple committee members should be deployed."""
    return (
        _should_deploy_oracle_committee(args)
        and args.get("agg_oracle_committee_total_members", 0) > 1
    )


def _should_deploy_validator_services(args):
    """Check if validator services should be deployed."""
    return (
        args.get("use_agg_sender_validator", False)
        and args.get("agg_sender_validator_total_number", 0) > 1
    )


def get_keystores_artifacts(plan, args):
    """Get all keystore artifacts needed for aggkit services."""
    aggoracle_keystore_artifact = plan.store_service_files(
        name="aggoracle-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/aggoracle.keystore",
    )
    sovereignadmin_keystore_artifact = plan.store_service_files(
        name="sovereignadmin-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/sovereignadmin.keystore",
    )
    sequencer_keystore_artifact = plan.store_service_files(
        name="aggkit-sequencer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/sequencer.keystore",
    )

    # Get claim sponsor keystore if it exists
    claim_sponsor_keystore_artifact = None
    if args.get("enable_aggkit_claim_sponsor", False):
        claim_sponsor_keystore_artifact = plan.store_service_files(
            name="claim-sponsor-keystore",
            service_name="contracts" + args["deployment_suffix"],
            src=constants.KEYSTORES_DIR + "/claimsponsor.keystore",
        )

    # Store multiple aggoracle committee member keystores
    committee_keystores = []
    if args.get("use_agg_oracle_committee", False):
        agg_oracle_committee_total_members = args.get(
            "agg_oracle_committee_total_members", 1
        )
        for member_index in range(agg_oracle_committee_total_members):
            committee_keystore = plan.store_service_files(
                name="aggoracle-{}-keystore".format(member_index),
                service_name="contracts" + args["deployment_suffix"],
                src=constants.KEYSTORES_DIR
                + "/aggoracle-{}.keystore".format(member_index),
            )
            committee_keystores.append(committee_keystore)
    else:
        # For non-committee mode, use the standard aggoracle keystore as the first committee member
        committee_keystores.append(aggoracle_keystore_artifact)

    # Store multiple aggsender validator keystores
    aggsender_validator_keystores = []
    if args.get("use_agg_sender_validator", False):
        agg_sender_validator_total_members = args.get(
            "agg_sender_validator_total_number", 1
        )
        # For loop starts from 1 instead of 0 for aggsender-validator service suffix consistency
        for member_index in range(2, agg_sender_validator_total_members + 1):
            aggsender_validator_keystore = plan.store_service_files(
                name="aggsendervalidator-{}-keystore".format(member_index),
                service_name="contracts" + args["deployment_suffix"],
                src=constants.KEYSTORES_DIR
                + "/aggsendervalidator-{}.keystore".format(member_index),
            )
            aggsender_validator_keystores.append(aggsender_validator_keystore)

    return struct(
        aggoracle=aggoracle_keystore_artifact,
        sovereignadmin=sovereignadmin_keystore_artifact,
        sequencer=sequencer_keystore_artifact,
        claim_sponsor=claim_sponsor_keystore_artifact,
        committee_keystores=committee_keystores,
        aggsender_validator_keystores=aggsender_validator_keystores,
    )


def create_bridge_config_artifact(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    db_configs,
):
    bridge_config_template = read_file(
        src="../../../static_files/zkevm-bridge-service/config.toml"
    )
    l1_rpc_url = args["mitm_rpc_url"].get("aggkit", args["l1_rpc_url"])
    if args["sequencer_type"] == constants.SEQUENCER_TYPE.cdk_erigon and (
        args["consensus_contract_type"]
        in [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.CONSENSUS_TYPE.ecdsa_multisig,
        ]
    ):
        l2_rpc_url = "http://{}{}:{}".format(
            args["l2_rpc_name"],
            args["deployment_suffix"],
            ports_package.HTTP_RPC_PORT_NUMBER,
        )
        require_sovereign_chain_contract = False
    else:
        l2_rpc_url = args["op_el_rpc_url"]
        require_sovereign_chain_contract = True

    return plan.render_templates(
        name="bridge-config{}".format(args.get("deployment_suffix")),
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "log_level": args.get("log_level"),
                    "environment": args.get("environment"),
                    "l2_keystore_password": args["l2_keystore_password"],
                    "db": db_configs.get("bridge_db"),
                    "require_sovereign_chain_contract": require_sovereign_chain_contract,
                    "sequencer_type": args["sequencer_type"],
                    # rpc urls
                    "l1_rpc_url": l1_rpc_url,
                    "l2_rpc_url": l2_rpc_url,
                    # ports
                    "grpc_port_number": args["zkevm_bridge_grpc_port"],
                    "rpc_port_number": args["zkevm_bridge_rpc_port"],
                    "metrics_port_number": args["zkevm_bridge_metrics_port"],
                }
                | contract_setup_addresses
                | sovereign_contract_setup_addresses,
            )
        },
    )


# Function to allow aggkit-config to pick whether to use agglayer_readrpc_port or agglayer_grpc_port depending on whether cdk-node or aggkit-node is being deployed.
# v0.2.0 aggkit only supports readrpc, and v0.3.0 or greater aggkit supports grpc.
def _get_agglayer_endpoint(aggkit_image):
    # If the aggkit image is a local build, we assume it uses grpc.
    if "local" in aggkit_image:
        return "grpc"

    # Extract the aggkit version from the image name.
    version = _extract_aggkit_version(aggkit_image)
    if version >= 0.3:
        return "grpc"
    else:
        return "readrpc"


def _extract_aggkit_version(aggkit_image):
    """Extract the version from the aggkit image name and return a float."""

    # ghcr.io/agglayer/aggkit:v0.5.0-beta1 -> v0.5.0-beta1
    tag = aggkit_image.split(":")[-1]

    # Aggkit CI will use aggkit:local to test latest changes.
    # Assume local is the latest version
    if tag == "local":
        return 999.9

    # v0.5.0-beta1 -> v0.5.0
    tag_without_suffix = tag.split("-")[0]

    # v0.5.0-beta1 -> 0.5.0
    version = tag_without_suffix
    for i in range(len(tag_without_suffix)):
        if tag_without_suffix[i].isdigit():
            version = tag_without_suffix[i:]
            break

    # return a float
    if version.count(".") > 1:
        split = version.split(".")
        return float("{}.{}".format(split[0], split[1]))
    return float(version)
