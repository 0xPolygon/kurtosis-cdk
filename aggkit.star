data_availability_package = import_module("./lib/data_availability.star")
aggkit_package = import_module("./lib/aggkit.star")
databases = import_module("./databases.star")
zkevm_bridge_package = import_module("./lib/zkevm_bridge.star")


def run(plan, args, contract_setup_addresses, sovereign_contract_setup_addresses):
    # Create aggkit-prover
    aggkit_prover_config_artifact = create_aggkit_prover_config_artifact(plan, args)
    (ports, public_ports) = get_aggkit_prover_ports(args)

    prover_env_vars = {}

    aggkit_prover = plan.add_service(
        name="aggkit-prover",
        config=ServiceConfig(
            image=args["aggkit_prover_image"],
            ports=ports,
            public_ports=public_ports,
            files={
                "/etc/aggkit": Directory(
                    artifact_names=[
                        aggkit_prover_config_artifact,
                    ]
                ),
            },
            entrypoint=[
                "/usr/local/bin/aggkit-prover",
            ],
            env_vars=prover_env_vars,
            cmd=["run", "--config", "/etc/aggkit/aggkit-prover-config.toml"],
        ),
    )
    aggkit_prover_url = "http://{}:{}".format(
        aggkit_prover.ip_address, aggkit_prover.ports["api"].number
    )

    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    keystore_artifacts = get_keystores_artifacts(plan, args)

    # Create the cdk aggoracle config.
    aggkit_config_template = read_file(src="./templates/aggkit/aggkit-config.toml")
    aggkit_config_artifact = plan.render_templates(
        name="cdk-aggoracle-config-artifact",
        config={
            "config.toml": struct(
                template=aggkit_config_template,
                data=args
                | {
                    "is_cdk_validium": data_availability_package.is_cdk_validium(args),
                }
                | db_configs
                | contract_setup_addresses
                | sovereign_contract_setup_addresses,
            )
        },
    )

    sovereign_genesis_file = read_file(src=args["sovereign_genesis_file"])
    sovereign_genesis_artifact = plan.render_templates(
        name="sovereign_genesis",
        config={"genesis.json": struct(template=sovereign_genesis_file, data={})},
    )

    # Start the aggoracle components.
    aggkit_configs = aggkit_package.create_aggkit_service_config(
        args, aggkit_config_artifact, sovereign_genesis_artifact, keystore_artifacts
    )

    plan.add_services(
        configs=aggkit_configs,
        description="Starting the cdk aggkit components",
    )

    # Start the bridge service.
    bridge_config_artifact = create_bridge_config_artifact(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        db_configs,
    )
    bridge_service_config = zkevm_bridge_package.create_bridge_service_config(
        args, bridge_config_artifact, keystore_artifacts.claimtx
    )
    plan.add_service(
        name="sovereign-bridge-service" + args["deployment_suffix"],
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
        name="claimtx-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/claimtx.keystore",
    )
    return struct(
        aggoracle=aggoracle_keystore_artifact,
        sovereignadmin=sovereignadmin_keystore_artifact,
        claimtx=claimtx_keystore_artifact,
    )


def create_bridge_config_artifact(
    plan, args, contract_setup_addresses, sovereign_contract_setup_addresses, db_configs
):
    bridge_config_template = read_file(
        src="./templates/sovereign-rollup/sovereign-bridge-config.toml"
    )
    return plan.render_templates(
        name="sovereign-bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "global_log_level": args["global_log_level"],
                    "l1_rpc_url": args["mitm_rpc_url"].get(
                        "aggkit", args["l1_rpc_url"]
                    ),
                    "l2_rpc_name": args["l2_rpc_name"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    "op_el_rpc_url": args["op_el_rpc_url"],
                    "op_cl_rpc_url": args["op_cl_rpc_url"],
                    # ports
                    "zkevm_bridge_grpc_port": args["zkevm_bridge_grpc_port"],
                    "zkevm_bridge_rpc_port": args["zkevm_bridge_rpc_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "zkevm_bridge_metrics_port": args["zkevm_bridge_metrics_port"],
                }
                | contract_setup_addresses
                | sovereign_contract_setup_addresses
                | db_configs,
            )
        },
    )


def create_aggkit_prover_config_artifact(plan, args):
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
                    "global_log_level": args["global_log_level"],
                    # ports
                    "aggkit_prover_port": args["aggkit_prover_port"],
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
                    "rollup_manager_address": args["zkevm_rollup_manager_address"],
                    "global_exit_root_address": args["zkevm_global_exit_root_address"],

                    "proposer_url": args[""],
                    "network_id": 1,
                    "aggkit_prover_network_url": args["aggkit_prover_network_url"]

                },
            )
        },
    )


def get_aggkit_prover_ports(args):
    ports = {
        "grpc": PortSpec(args["aggkit_prover_port"], application_protocol="http"),
        "metrics": PortSpec(
            args["aggkit_prover_metrics_port"], application_protocol="http"
        ),
    }
    public_ports = ports_package.get_public_ports(
        ports, "aggkit_prover_start_port", args
    )
    return (ports, public_ports)
