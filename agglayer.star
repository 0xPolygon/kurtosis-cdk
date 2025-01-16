databases_package = import_module("./databases.star")
ports_package = import_module("./src/package_io/ports.star")


def run(plan, args, contract_setup_addresses):
    # Create agglayer prover service.
    agglayer_prover_config_artifact = create_agglayer_prover_config_artifact(plan, args)
    (ports, public_ports) = get_agglayer_prover_ports(args)

    prover_env_vars = {}

    prover_env_vars["RUST_BACKTRACE"] = "1"
    if "agglayer_prover_sp1_key" in args and args["agglayer_prover_sp1_key"] != None:
        prover_env_vars["NETWORK_PRIVATE_KEY"] = args["agglayer_prover_sp1_key"]
        # Keeping this for backward compatibility for now
        prover_env_vars["SP1_PRIVATE_KEY"] = args["agglayer_prover_sp1_key"]
        prover_env_vars["NETWORK_RPC_URL"] = args["agglayer_prover_network_url"]

    agglayer_prover = plan.add_service(
        name="agglayer-prover",
        config=ServiceConfig(
            image=args["agglayer_image"],
            ports=ports,
            public_ports=public_ports,
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[
                        agglayer_prover_config_artifact,
                    ]
                ),
            },
            entrypoint=[
                "/usr/local/bin/agglayer",
            ],
            env_vars=prover_env_vars,
            cmd=["prover", "--cfg", "/etc/zkevm/agglayer-prover-config.toml"],
        ),
        description="AggLayer Prover",
    )
    agglayer_prover_url = "http://{}:{}".format(
        agglayer_prover.ip_address, agglayer_prover.ports["api"].number
    )

    # Deploy agglayer service.
    agglayer_config_artifact = create_agglayer_config_artifact(
        plan, args, agglayer_prover_url, contract_setup_addresses
    )
    agglayer_keystore_artifact = plan.store_service_files(
        name="agglayer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/agglayer.keystore",
    )

    (ports, public_ports) = get_agglayer_ports(args)
    plan.add_service(
        name="agglayer",
        config=ServiceConfig(
            image=args["agglayer_image"],
            ports=ports,
            public_ports=public_ports,
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[
                        agglayer_config_artifact,
                        agglayer_keystore_artifact,
                    ]
                ),
            },
            entrypoint=[
                "/usr/local/bin/agglayer",
            ],
            cmd=["run", "--cfg", "/etc/zkevm/agglayer-config.toml"],
        ),
        description="AggLayer",
    )


def create_agglayer_prover_config_artifact(plan, args):
    agglayer_prover_config_template = read_file(
        src="./templates/bridge-infra/agglayer-prover-config.toml"
    )

    is_cpu_prover_enabled = "true"
    is_network_prover_enabled = "false"
    if "agglayer_prover_sp1_key" in args and args["agglayer_prover_sp1_key"] != None:
        is_cpu_prover_enabled = "false"
        is_network_prover_enabled = "true"

    return plan.render_templates(
        name="agglayer-prover-config-artifact",
        config={
            "agglayer-prover-config.toml": struct(
                template=agglayer_prover_config_template,
                # TODO: Organize those args.
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "global_log_level": args["global_log_level"],
                    # ports
                    "agglayer_prover_port": args["agglayer_prover_port"],
                    "prometheus_port": args["agglayer_prover_metrics_port"],
                    "is_cpu_prover_enabled": is_cpu_prover_enabled,
                    "is_network_prover_enabled": is_network_prover_enabled,
                },
            )
        },
    )


def create_agglayer_config_artifact(
    plan, args, agglayer_prover_url, contract_setup_addresses
):
    agglayer_config_template = read_file(
        src="./templates/bridge-infra/agglayer-config.toml"
    )
    db_configs = databases_package.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )
    return plan.render_templates(
        name="agglayer-config-artifact",
        config={
            "agglayer-config.toml": struct(
                template=agglayer_config_template,
                # TODO: Organize those args.
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "global_log_level": args["global_log_level"],
                    "l1_chain_id": args["l1_chain_id"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l1_ws_url": args["l1_ws_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    "zkevm_l2_proofsigner_address": args[
                        "zkevm_l2_proofsigner_address"
                    ],
                    "zkevm_l2_sequencer_address": args["zkevm_l2_sequencer_address"],
                    # ports
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "agglayer_port": args["agglayer_port"],
                    "agglayer_prover_entrypoint": agglayer_prover_url,
                    "prometheus_port": args["agglayer_metrics_port"],
                    "l2_rpc_name": args["l2_rpc_name"],
                }
                | contract_setup_addresses
                | db_configs,
            )
        },
    )


def get_agglayer_prover_ports(args):
    ports = {
        "api": PortSpec(args["agglayer_prover_port"], application_protocol="grpc"),
        "prometheus": PortSpec(
            args["agglayer_prover_metrics_port"], application_protocol="http"
        ),
    }
    public_ports = ports_package.get_public_ports(
        ports, "agglayer_prover_start_port", args
    )
    return (ports, public_ports)


def get_agglayer_ports(args):
    ports = {
        "agglayer": PortSpec(args["agglayer_port"], application_protocol="http"),
        "prometheus": PortSpec(
            args["agglayer_metrics_port"], application_protocol="http"
        ),
    }
    public_ports = ports_package.get_public_ports(ports, "agglayer_start_port", args)
    return (ports, public_ports)
