databases_package = import_module("./databases.star")
service_package = import_module("./lib/service.star")
ports_package = import_module("./src/package_io/ports.star")


def run(plan, args):
    # Create agglayer prover service.
    agglayer_prover_config_artifact = create_agglayer_prover_config_artifact(plan, args)
    prover = plan.add_service(
        name="agglayer-prover",
        config=ServiceConfig(
            image=args["agglayer_image"],
            ports={
                "api": PortSpec(
                    args["agglayer_prover_port"], application_protocol="grpc"
                ),
                "prometheus": PortSpec(
                    args["agglayer_prover_metrics_port"], application_protocol="http"
                ),
            },
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
            cmd=["prover", "--cfg", "/etc/zkevm/agglayer-prover-config.toml"],
        ),
        description="AggLayer Prover",
    )

    # Deploy agglayer service.
    agglayer_config_artifact = create_agglayer_config_artifact(plan, args)
    agglayer_keystore_artifact = plan.store_service_files(
        name="agglayer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/agglayer.keystore",
    )

    plan.add_service(
        name="agglayer",
        config=ServiceConfig(
            image=args["agglayer_image"],
            ports={
                "agglayer": PortSpec(
                    args["agglayer_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["agglayer_metrics_port"], application_protocol="http"
                ),
            },
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
                },
            )
        },
    )


def create_agglayer_config_artifact(plan, args, contract_setup_addresses, db_configs):
    agglayer_config_template = read_file(
        src="./templates/bridge-infra/agglayer-config.toml"
    )
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
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
                    "agglayer_prover_entrypoint": "http://agglayer-prover:{}".format(
                        args["agglayer_prover_port"]
                    ),
                    "prometheus_port": args["agglayer_metrics_port"],
                    "l2_rpc_name": args["l2_rpc_name"],
                }
                | contract_setup_addresses
                | db_configs,
            )
        },
    )
