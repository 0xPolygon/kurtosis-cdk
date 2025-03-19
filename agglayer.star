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
                    "zkevm_rollup_fork_id": args["zkevm_rollup_fork_id"],
                    # ports
                    "agglayer_prover_port": args["agglayer_prover_port"],
                    "prometheus_port": args["agglayer_prover_metrics_port"],
                    # prover settings (fork9/11)
                    "is_cpu_prover_enabled": is_cpu_prover_enabled,
                    "is_network_prover_enabled": is_network_prover_enabled,
                    # prover settings (fork12+)
                    "primary_prover": args["agglayer_prover_primary_prover"],
                },
            )
        },
    )


def agglayer_version(args):
    if "agglayer_version" in args:
        return args["agglayer_version"]
    elif "agglayer_image" in args and ":" in args["agglayer_image"]:
        return args["agglayer_image"].split(":")[1]
    else:
        return "latest"


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
                    "l1_rpc_url": args["mitm_rpc_url"].get(
                        "agglayer", args["l1_rpc_url"]
                    ),
                    "l1_ws_url": args["l1_ws_url"],
                    "zkevm_rollup_fork_id": args["zkevm_rollup_fork_id"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    "zkevm_l2_proofsigner_address": args[
                        "zkevm_l2_proofsigner_address"
                    ],
                    "zkevm_l2_sequencer_address": args["zkevm_l2_sequencer_address"],
                    # ports
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "agglayer_version": agglayer_version(args),
                    "agglayer_grpc_port": args["agglayer_grpc_port"],
                    "agglayer_readrpc_port": args["agglayer_readrpc_port"],
                    "agglayer_prover_entrypoint": agglayer_prover_url,
                    "prometheus_port": args["agglayer_metrics_port"],
                    "l2_rpc_name": args["l2_rpc_name"],
                    # verifier
                    "mock_verifier": args["agglayer_prover_primary_prover"]
                    == "mock-prover",
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
        "aglr-readrpc": PortSpec(
            args["agglayer_readrpc_port"], application_protocol="http"
        ),
        "prometheus": PortSpec(
            args["agglayer_metrics_port"], application_protocol="http"
        ),
    }
    if not agglayer_version(args).startswith("0.2."):
        ports["aglr-grpc"] = PortSpec(
            args["agglayer_grpc_port"], application_protocol="http"
        )
    public_ports = ports_package.get_public_ports(ports, "agglayer_start_port", args)
    return (ports, public_ports)
