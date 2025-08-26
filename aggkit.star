constants = import_module("./src/package_io/constants.star")
data_availability_package = import_module("./lib/data_availability.star")
aggkit_package = import_module("./lib/aggkit.star")
databases = import_module("./databases.star")
zkevm_bridge_package = import_module("./lib/zkevm_bridge.star")
ports_package = import_module("./src/package_io/ports.star")
service_package = import_module("./lib/service.star")


def run_aggkit_cdk_node(
    plan,
    args,
    contract_setup_addresses,
    deployment_stages,
):
    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    # Create the aggkit cdk config.
    aggkit_cdk_config_template = read_file(
        src="./templates/aggkit/aggkit-cdk-config.toml"
    )
    aggkit_config_artifact = plan.render_templates(
        name="aggkit-cdk-config-artifact",
        config={
            "config.toml": struct(
                template=aggkit_cdk_config_template,
                data=args
                | {
                    "is_cdk_validium": data_availability_package.is_cdk_validium(args),
                }
                | db_configs
                | contract_setup_addresses,
            )
        },
    )

    keystore_artifacts = get_keystores_artifacts(plan, args)

    # Start the components.
    aggkit_configs = aggkit_package.create_aggkit_cdk_service_config(
        plan, args, aggkit_config_artifact, keystore_artifacts
    )

    plan.add_services(
        configs=aggkit_configs,
        description="Starting the cdk aggkit components",
    )


def run(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
):
    if (
        deployment_stages.get("deploy_op_succinct", False)
        and args["consensus_contract_type"] != "pessimistic"
    ):
        # Create aggkit-prover
        aggkit_prover_config_artifact = create_aggkit_prover_config_artifact(
            plan, args, contract_setup_addresses, sovereign_contract_setup_addresses
        )
        (ports, public_ports) = get_aggkit_prover_ports(args)

        # Fetch evm-sketch-genesis-conf artifact
        evm_sketch_genesis_conf = get_evm_sketch_genesis(plan, args)

        prover_env_vars = {
            # TODO one of these values can be deprecated soon 2025-04-15
            "PROPOSER_NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
            "NETWORK_PRIVATE_KEY": args["sp1_prover_key"],
            "RUST_LOG": "info,aggkit_prover=debug,prover=debug,aggchain=debug",
            "RUST_BACKTRACE": "1",
        }

        aggkit_prover = plan.add_service(
            name="aggkit-prover" + args["deployment_suffix"],
            config=ServiceConfig(
                image=args["aggkit_prover_image"],
                ports=ports,
                public_ports=public_ports,
                files={
                    "/etc/aggkit": Directory(
                        artifact_names=[
                            aggkit_prover_config_artifact,
                            evm_sketch_genesis_conf,
                        ]
                    ),
                },
                entrypoint=[
                    "/usr/local/bin/aggkit-prover",
                ],
                env_vars=prover_env_vars,
                cmd=["run", "--config-path", "/etc/aggkit/aggkit-prover-config.toml"],
            ),
        )
        aggkit_prover_url = "{}:{}".format(
            aggkit_prover.ip_address,
            aggkit_prover.ports[
                "grpc"
            ].number,  # TODO: Check whether "grpc" or "api" is the correct port. If api is correct, we need to add it below.
        )

    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    keystore_artifacts = get_keystores_artifacts(plan, args)
    l2_rpc_url = "http://{}{}:{}".format(
        args["l2_rpc_name"], args["deployment_suffix"], args["zkevm_rpc_http_port"]
    )
    if args["use_agg_oracle_committee"]:
        # Fetch aggoracle_commitee_address
        aggoracle_committee_address = service_package.get_aggoracle_committee_address(
            plan, args
        )
        sovereign_contract_setup_addresses = (
            sovereign_contract_setup_addresses | aggoracle_committee_address
        )

    # Create the cdk aggkit config.
    agglayer_endpoint = _get_agglayer_endpoint(args.get("aggkit_image"))
    aggkit_config_template = read_file(src="./templates/aggkit/aggkit-config.toml")

    sovereign_genesis_file = read_file(src=args["sovereign_genesis_file"])
    sovereign_genesis_artifact = plan.render_templates(
        name="sovereign_genesis",
        config={"genesis.json": struct(template=sovereign_genesis_file, data={})},
    )

    # Start multiple aggoracle components based on committee size
    aggkit_configs = {}
    committee_total_members = args.get("agg_oracle_committee_total_members", 1)
    
    for member_index in range(committee_total_members):
        # Create individual config for each committee member
        aggkit_config_artifact = plan.render_templates(
            name="aggkit-config-artifact-{}".format(member_index),
            config={
                "config.toml": struct(
                    template=aggkit_config_template,
                    data=args
                    | deployment_stages
                    | {
                        "is_cdk_validium": data_availability_package.is_cdk_validium(args),
                        "agglayer_endpoint": agglayer_endpoint,
                        "l2_rpc_url": l2_rpc_url,
                        "committee_member_index": member_index,
                    }
                    | db_configs
                    | contract_setup_addresses
                    | sovereign_contract_setup_addresses,
                )
            },
        )

        # Create aggkit service config for each committee member
        member_aggkit_configs = aggkit_package.create_aggkit_service_config(
            plan,
            args,
            aggkit_config_artifact,
            sovereign_genesis_artifact,
            keystore_artifacts,
            member_index,
        )
        
        # Merge configs
        aggkit_configs.update(member_aggkit_configs)

    plan.add_services(
        configs=aggkit_configs,
        description="Starting the cdk aggkit components for all committee members",
    )

    # Start the bridge service only once (not per committee member)
    if deployment_stages.get("deploy_cdk_bridge_infra"):
        bridge_config_artifact = create_bridge_config_artifact(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            db_configs,
            deployment_stages,
        )
        bridge_service_config = zkevm_bridge_package.create_bridge_service_config(
            args, bridge_config_artifact, keystore_artifacts.claimtx
        )
        plan.add_service(
            name="zkevm-bridge-service" + args["deployment_suffix"],
            config=bridge_service_config,
        )


def get_keystores_artifacts(plan, args):
    aggoracle_keystore_artifact = plan.store_service_files(
        name="aggoracle-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/aggoracle.keystore",
    )
    sovereignadmin_keystore_artifact = plan.store_service_files(
        name="sovereignadmin-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/sovereignadmin.keystore",
    )
    claimtx_keystore_artifact = plan.store_service_files(
        name="aggkit-claimtxmanager-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/claimtxmanager.keystore",
    )
    sequencer_keystore_artifact = plan.store_service_files(
        name="aggkit-sequencer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/sequencer.keystore",
    )
    claim_sponsor_keystore_artifact = plan.store_service_files(
        name="claimsponsor-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/claimsponsor.keystore",
    )
    aggkit_validator_keystore_artifact = plan.store_service_files(
        name="aggkitvalidator-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/aggkitvalidator.keystore",
    )
    
    # Store multiple aggoracle committee member keystores
    committee_keystores = []
    committee_total_members = args.get("agg_oracle_committee_total_members", 1)
    for member_index in range(committee_total_members):
        committee_keystore = plan.store_service_files(
            name="aggoracle-{}-keystore".format(member_index),
            service_name="contracts" + args["deployment_suffix"],
            src="/opt/zkevm/aggoracle-{}.keystore".format(member_index),
        )
        committee_keystores.append(committee_keystore)
    
    return struct(
        aggoracle=aggoracle_keystore_artifact,
        sovereignadmin=sovereignadmin_keystore_artifact,
        claimtx=claimtx_keystore_artifact,
        sequencer=sequencer_keystore_artifact,
        claim_sponsor=claim_sponsor_keystore_artifact,
        aggkit_validator=aggkit_validator_keystore_artifact,
        committee_keystores=committee_keystores,
    )


def create_bridge_config_artifact(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    db_configs,
    deployment_stages,
):
    bridge_config_template = read_file(
        src="./templates/bridge-infra/bridge-config.toml"
    )
    l1_rpc_url = args["mitm_rpc_url"].get("aggkit", args["l1_rpc_url"])
    if (
        not deployment_stages.get("deploy_optimism_rollup", False)
        and args["consensus_contract_type"] == constants.CONSENSUS_TYPE.pessimistic
    ):
        l2_rpc_url = "http://{}{}:{}".format(
            args["l2_rpc_name"], args["deployment_suffix"], args["zkevm_rpc_http_port"]
        )
        contract_addresses = contract_setup_addresses
        require_sovereign_chain_contract = False
    else:
        l2_rpc_url = args["op_el_rpc_url"]
        contract_addresses = contract_setup_addresses | {
            "zkevm_rollup_address": sovereign_contract_setup_addresses.get(
                "sovereign_rollup_addr"
            ),
            "zkevm_bridge_l2_address": sovereign_contract_setup_addresses.get(
                "sovereign_bridge_proxy_addr"
            ),
            "zkevm_global_exit_root_l2_address": sovereign_contract_setup_addresses.get(
                "sovereign_ger_proxy_addr"
            ),
        }
        require_sovereign_chain_contract = True
    return plan.render_templates(
        name="bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "global_log_level": args["global_log_level"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    "db": db_configs.get("bridge_db"),
                    "require_sovereign_chain_contract": require_sovereign_chain_contract,
                    # rpc urls
                    "l1_rpc_url": l1_rpc_url,
                    "l2_rpc_url": l2_rpc_url,
                    # ports
                    "grpc_port_number": args["zkevm_bridge_grpc_port"],
                    "rpc_port_number": args["zkevm_bridge_rpc_port"],
                    "metrics_port_number": args["zkevm_bridge_metrics_port"],
                }
                | contract_addresses,
            )
        },
    )


def create_aggkit_prover_config_artifact(
    plan, args, contract_setup_addresses, sovereign_contract_setup_addresses
):
    aggkit_prover_config_template = read_file(
        src="./templates/bridge-infra/aggkit-prover-config.toml"
    )

    return plan.render_templates(
        name="aggkit-prover-artifact",
        config={
            "aggkit-prover-config.toml": struct(
                template=aggkit_prover_config_template,
                # TODO: Organize those args.
                data={
                    "log_level": args["aggkit_prover_log_level"],
                    # ports
                    "aggkit_prover_grpc_port": args["aggkit_prover_grpc_port"],
                    "metrics_port": args["aggkit_prover_metrics_port"],
                    # prover settings (fork12+)
                    "primary_prover": args["aggkit_prover_primary_prover"],
                    # L1
                    # TODO: Is it the right way of creating the L1_RPC_URL for aggkit related component ?
                    "l1_rpc_url": args["mitm_rpc_url"].get(
                        "aggkit", args["l1_rpc_url"]
                    ),
                    # L2
                    "l2_el_rpc_url": args["op_el_rpc_url"],
                    "l2_cl_rpc_url": args["op_cl_rpc_url"],
                    "rollup_manager_address": contract_setup_addresses[
                        "zkevm_rollup_manager_address"
                    ],  # TODO: Check if it's the right address - is it the L1 rollup manager address ?
                    "global_exit_root_address": sovereign_contract_setup_addresses[
                        "sovereign_ger_proxy_addr"
                    ],  # TODO: Check if it's the right address - is it the L2 sovereign global exit root address ?
                    # TODO: For op-succinct, agglayer/op-succinct is currently on the golang version. This might change if we move to the rust version.
                    "proposer_url": "http://op-succinct-proposer{}:{}".format(
                        args["deployment_suffix"],
                        args["op_succinct_proposer_grpc_port"],
                    ),
                    # TODO: For legacy op, this would be different - something like http://op-proposer-001:8560
                    # "proposer_url": "http://op-proposer{}:{}".format(
                    #     args["deployment_suffix"], args["op_proposer_port"]
                    # ),
                    "network_id": args["zkevm_rollup_id"],
                    "agglayer_prover_network_url": args["agglayer_prover_network_url"],
                    "op_succinct_mock": args["op_succinct_mock"],
                },
            )
        },
    )


def get_aggkit_prover_ports(args):
    ports = {
        "grpc": PortSpec(args["aggkit_prover_grpc_port"], application_protocol="grpc"),
        "metrics": PortSpec(
            args["aggkit_prover_metrics_port"], application_protocol="http"
        ),
    }
    public_ports = ports_package.get_public_ports(
        ports, "aggkit_prover_start_port", args
    )
    return (ports, public_ports)


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


# Fetch the parsed .config section of L1 geth genesis.
def get_evm_sketch_genesis(plan, args):
    # Upload file to files artifact
    evm_sketch_genesis_conf_artifact = plan.store_service_files(
        service_name="temp-contracts",
        name="evm-sketch-genesis-conf-artifact.json",
        src="/opt/op-succinct/evm-sketch-genesis.json",
        description="Storing evm-sketch-genesis.json for evm-sketch-genesis field in aggkit-prover.",
    )

    # Fetch evm-sketch-genesis-conf artifact
    evm_sketch_genesis_conf = plan.get_files_artifact(
        name="evm-sketch-genesis-conf-artifact.json",
        description="Fetch evm-sketch-genesis-conf-artifact.json files artifact",
    )

    # Remove temp-contracts service after extracting evm-sketch-genesis
    plan.remove_service(
        name="temp-contracts",
        description="Remove temp-contracts service after extracting evm-sketch-genesis",
    )

    return evm_sketch_genesis_conf
