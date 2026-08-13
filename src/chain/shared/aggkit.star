aggkit_prover = import_module("./aggkit_prover.star")
constants = import_module("../../package_io/constants.star")
databases = import_module("../shared/databases.star")
ports_package = import_module("./ports.star")
contracts_util = import_module("../../contracts/util.star")
op_succinct = import_module("../op-reth/op_succinct_proposer.star")


def run_aggkit_cdk_node(plan, args, contract_setup_addresses):
    """Deploy aggkit CDK node with inline config creation."""
    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    # Create config artifact
    config_template = read_file(
        src="../../../static_files/chain/shared/aggkit/cdk-config.toml"
    )
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
                    "aggkit_legacy_bridge_addr": not _aggkit_version_gte(
                        args.get("aggkit_image"), 0, 8
                    ),
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
    deployment_stages,
):
    """Main orchestration function for deploying aggkit services."""
    # Deploy OP Succinct if needed
    deploy_op_succinct = deployment_stages.get("deploy_op_succinct", False)
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
    bridge_service = _deploy_core_aggkit_services(plan, args, deployment_context)
    bridge_url = bridge_service.ports["rest"].url

    # Deploy committee members if needed
    _deploy_committee_members_if_needed(plan, args, deployment_context)

    # Deploy validator services if needed
    _deploy_validator_services_if_needed(plan, args, deployment_context)

    return bridge_url


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
    """Deploy the core aggkit service (main service, with the bridge component
    merged in -- see _deploy_main_aggkit_service)."""
    plan.print("Deploying core aggkit services")

    # Create main aggkit service (also serves the bridge REST API) with inline config
    return _deploy_main_aggkit_service(plan, args, deployment_context)


def _deploy_main_aggkit_service(plan, args, deployment_context):
    """Deploy the main aggkit service with inline config creation. This
    service also serves the bridge component (REST API) -- the bridge is no
    longer a separate service/container, see aggkit_components."""
    # Create config artifact
    config_template = read_file(
        src="../../../static_files/chain/shared/aggkit/config.toml"
    )
    config_artifact = plan.render_templates(
        name="aggkit-config{}".format(args.get("deployment_suffix")),
        config={
            "config.toml": struct(
                template=config_template,
                data=_build_config_data(args, deployment_context),
            )
        },
    )

    # Log warnings if needed
    _log_claim_sponsor_warning(plan, args)
    _log_autoclaim_warning(plan, args)

    # Create and deploy service
    service_name = "aggkit" + args["deployment_suffix"]
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

    return plan.add_service(name=service_name, config=service_config)


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
    config_template = read_file(
        src="../../../static_files/chain/shared/aggkit/config.toml"
    )
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
    config_template = read_file(
        src="../../../static_files/chain/shared/aggkit/config.toml"
    )
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
            # Decide this in Starlark rather than inside the Go template: Kurtosis
            # stringifies aggkit_version before handing it to text/template, so
            # `{{- if lt .aggkit_version "0.8" }}` there does a lexicographic STRING
            # comparison, and "0.11" < "0.8" is true digit-by-digit -- wrongly gating
            # the legacy/deprecated polygonBridgeAddr key on for aggkit 0.11.x.
            # _aggkit_version_gte parses major/minor as integers and compares them
            # as a tuple -- correct regardless of minor-version digit count. See
            # config.toml / cdk-config.toml.
            "aggkit_legacy_bridge_addr": not _aggkit_version_gte(
                args.get("aggkit_image"), 0, 8
            ),
            "l2_rpc_url": deployment_context.l2_rpc_url,
            "aggkit_prover_grpc_port_number": aggkit_prover.GRPC_PORT_NUMBER,
            # Whether THIS instance's own destination network (l2_network_id)
            # is one of the networks this run wants an AutoClaim claimer for.
            # See aggkit_autoclaim_destinations in input_parser.star -- never
            # true for network 0 (L1), since l2_network_id is always an L2.
            "aggkit_autoclaim_enabled": args.get("l2_network_id")
            in args.get("aggkit_autoclaim_destinations", []),
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


def _log_autoclaim_warning(plan, args):
    """Warn if this instance's own network is an AutoClaim destination but the
    'autoclaim' component isn't in aggkit_components -- the [AutoClaim]
    config section would be rendered but the process would never run it."""
    is_autoclaim_destination = args.get("l2_network_id") in args.get(
        "aggkit_autoclaim_destinations", []
    )
    if is_autoclaim_destination:
        components = args.get("aggkit_components", "")
        if "autoclaim" not in components.split(","):
            plan.print(
                "⚠️  WARNING: this network_id is listed in aggkit_autoclaim_destinations, but 'autoclaim' is not included in aggkit_components — Auto Claim will be inert."
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


# Function to allow aggkit-config to pick whether to use agglayer_readrpc_port or agglayer_grpc_port depending on whether cdk-node or aggkit-node is being deployed.
# v0.2.0 aggkit only supports readrpc, and v0.3.0 or greater aggkit supports grpc.
#
# NOTE: this deliberately does NOT compare _extract_aggkit_version's float
# (`version >= 0.3`) -- that collapses "<major>.<minor>" into a single float,
# so "0.11" becomes 0.11, which is numerically LESS than 0.3 even though minor
# version 11 is ordinally newer than minor version 3. Verified empirically:
# for aggkit_image "...:0.11.0-rc4", the float comparison wrongly returns
# "readrpc", which breaks certificate settlement against agglayer. Uses
# _aggkit_version_gte instead, which parses major/minor as integers and
# compares them as a tuple -- correct regardless of minor-version digit count.
def _get_agglayer_endpoint(aggkit_image):
    # If the aggkit image is a local build, we assume it uses grpc.
    if "local" in aggkit_image:
        return "grpc"

    # Compare major.minor numerically so 0.10+ is not misread as 0.1 (< 0.3).
    if _aggkit_version_gte(aggkit_image, 0, 3):
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
    found_digit = False
    for i in range(len(tag_without_suffix)):
        if tag_without_suffix[i].isdigit():
            version = tag_without_suffix[i:]
            found_digit = True
            break

    # Some CI-built tags (e.g. feature-branch build tags like
    # "feat-autoclaim-l2-lx_2026_07_13_07_54_42f1a23") don't start with a
    # numeric version at all once the first "-"-delimited segment is taken.
    # Treat these the same as "local": assume they're built from the latest
    # source and are therefore the latest version (grpc-capable), instead of
    # hard-failing on float(<non-numeric string>).
    if not found_digit:
        return 999.9

    # Other CI-built tags DO start with a digit but are still not a clean
    # "<major>.<minor>[.<patch>]" version once the "-"-delimited suffix is
    # dropped -- e.g. "develop_2026_08_03_13_20_56c849c" (branch name +
    # underscore-joined build timestamp + short sha, no "-" at all so
    # tag_without_suffix is the whole tag, and it starts with the "2026"
    # digit of the date). float() would hard-fail on the underscores/hex
    # digits in that string, so treat non-numeric "versions" the same way:
    # assume latest (grpc-capable).
    if not _is_simple_version(version):
        return 999.9

    # return a float
    if version.count(".") > 1:
        split = version.split(".")
        return float("{}.{}".format(split[0], split[1]))
    return float(version)


def _is_simple_version(version):
    """True if version consists only of digits and '.' (i.e. is float()-safe)."""
    for i in range(len(version)):
        c = version[i]
        if c != "." and not c.isdigit():
            return False
    return True


def _aggkit_version_gte(aggkit_image, major, minor):
    """Return True if the aggkit image version is >= major.minor.

    Compares major/minor as integers so double-digit minors order correctly
    (0.10 > 0.9 > 0.8; 0.11 > 0.8 > 0.3). _extract_aggkit_version returns a
    float where "0.10"/"0.11" collapse to 0.1/0.11 (< 0.8, < 0.3), which
    silently breaks version-conditional config for aggkit >= 0.10; use this
    for those gates instead. Non-numeric tags (local builds, CI build tags)
    fall back to (0, 0) -- i.e. are treated as the oldest version -- since
    this package only ever pins numeric release tags in practice, except for
    the literal "local" tag which is treated as latest (see below).
    """
    if "local" in aggkit_image:
        return True

    tag = aggkit_image.split(":")[-1]
    if tag == "local":
        return True

    # v0.10.0-rc7 -> 0.10.0 (strip suffix, then any leading "v").
    tag_without_suffix = tag.split("-")[0]
    ver = tag_without_suffix
    for i in range(len(tag_without_suffix)):
        if tag_without_suffix[i].isdigit():
            ver = tag_without_suffix[i:]
            break

    parts = ver.split(".")
    v_major = int(parts[0]) if len(parts) > 0 and parts[0].isdigit() else 0
    v_minor = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0
    return (v_major, v_minor) >= (major, minor)
