constants = import_module("./package_io/constants.star")
databases_package = import_module("./chain/shared/databases.star")
ports_package = import_module("./chain/shared/ports.star")


def run(plan, deployment_stages, args, contract_setup_addresses):
    # Deploy agglayer service.
    agglayer_config_artifact = create_agglayer_config_artifact(
        plan, deployment_stages, args, contract_setup_addresses
    )
    aggregator_keystore_artifact = plan.store_service_files(
        name="aggregator-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/aggregator.keystore",
    )
    sp1_env_vars = {}
    sp1_env_vars["RUST_BACKTRACE"] = "1"
    if "sp1_prover_key" in args and args["sp1_prover_key"] != None:
        sp1_env_vars["NETWORK_PRIVATE_KEY"] = args["sp1_prover_key"]
        # Keeping this for backward compatibility for now
        sp1_env_vars["SP1_PRIVATE_KEY"] = args["sp1_prover_key"]
        sp1_env_vars["NETWORK_RPC_URL"] = args["sp1_cluster_endpoint"]

    ports = get_agglayer_ports(args)
    plan.add_service(
        name="agglayer",
        config=ServiceConfig(
            image=args["agglayer_image"],
            ports=ports,
            files={
                "/etc/agglayer": Directory(
                    artifact_names=[
                        agglayer_config_artifact,
                        aggregator_keystore_artifact,
                    ]
                ),
            },
            entrypoint=[
                "/usr/local/bin/agglayer",
            ],
            env_vars=sp1_env_vars,
            cmd=["run", "--cfg", "/etc/agglayer/config.toml"],
        ),
    )


def agglayer_version(args):
    if "agglayer_version" in args:
        return args["agglayer_version"]
    elif "agglayer_image" in args and ":" in args["agglayer_image"]:
        return args["agglayer_image"].split(":")[1]
    else:
        return "latest"


def create_agglayer_config_artifact(
    plan, deployment_stages, args, contract_setup_addresses
):
    agglayer_config_template = read_file(src="../static_files/agglayer/config.toml")
    db_configs = databases_package.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    return plan.render_templates(
        name="agglayer-config",
        config={
            "config.toml": struct(
                template=agglayer_config_template,
                # TODO: Organize those args.
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "log_level": args.get("log_level"),
                    "log_format": args.get("log_format"),
                    "l1_chain_id": args["l1_chain_id"],
                    "l1_rpc_url": args["mitm_rpc_url"].get(
                        "agglayer", args["l1_rpc_url"]
                    ),
                    "l1_ws_url": args["l1_ws_url"],
                    "zkevm_fork_id": args["zkevm_fork_id"],
                    "l2_keystore_password": args["l2_keystore_password"],
                    "l2_sequencer_address": args["l2_sequencer_address"],
                    # ports
                    "http_rpc_port_number": ports_package.HTTP_RPC_PORT_NUMBER,
                    "agglayer_version": agglayer_version(args),
                    "agglayer_grpc_port": args["agglayer_grpc_port"],
                    "agglayer_readrpc_port": args["agglayer_readrpc_port"],
                    "agglayer_prover_primary_prover": args.get(
                        "agglayer_prover_primary_prover"
                    ),
                    "sp1_cluster_endpoint": args.get("sp1_cluster_endpoint"),
                    "agglayer_admin_port": args["agglayer_admin_port"],
                    "prometheus_port": args["agglayer_metrics_port"],
                    "l2_rpc_name": args["l2_rpc_name"],
                    # verifier
                    "mock_verifier": args["agglayer_prover_primary_prover"]
                    == "mock-prover",
                    # op-stack
                    "sequencer_type": args["sequencer_type"],
                    "op_el_rpc_url": args["op_el_rpc_url"],
                    "l2_sovereignadmin_address": args["l2_sovereignadmin_address"],
                    "consensus_contract_type": args["consensus_contract_type"],
                }
                | contract_setup_addresses
                | db_configs,
            )
        },
    )


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
            args["agglayer_grpc_port"], application_protocol="grpc"
        )
        if args["agglayer_admin_port"] != 0:
            ports["aglr-admin"] = PortSpec(
                args["agglayer_admin_port"], application_protocol="http"
            )
    return ports
