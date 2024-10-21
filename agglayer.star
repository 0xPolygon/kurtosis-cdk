databases_package = import_module("./databases.star")
service_package = import_module("./lib/service.star")
ports_package = import_module("./src/package_io/ports.star")


def run(plan, args):
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    db_configs = databases_package.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )
    agglayer_config_artifact = create_agglayer_config_artifact(
        plan, args, contract_setup_addresses, db_configs
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


def create_agglayer_config_artifact(plan, args, contract_setup_addresses, db_configs):
    agglayer_config_template = read_file(
        src="./templates/bridge-infra/agglayer-config.toml"
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
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    "zkevm_l2_proofsigner_address": args[
                        "zkevm_l2_proofsigner_address"
                    ],
                    "zkevm_l2_sequencer_address": args["zkevm_l2_sequencer_address"],
                    # ports
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "agglayer_port": args["agglayer_port"],
                    "prometheus_port": args["prometheus_port"],
                    "l2_rpc_name": args["l2_rpc_name"],
                }
                | contract_setup_addresses
                | db_configs,
            )
        },
    )


def get_agglayer_ports(args):
    ports = {
        "agglayer": PortSpec(args["agglayer_port"], application_protocol="http"),
        "prometheus": PortSpec(args["prometheus_port"], application_protocol="http"),
    }
    public_ports = ports_package.get_public_ports(ports, "agglayer_start_port", args)
    return (ports, public_ports)
