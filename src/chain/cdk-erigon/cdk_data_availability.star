constants = import_module("../../package_io/constants.star")
databases = import_module("../shared/databases.star")


# Port identifiers and numbers.
RPC_PORT_ID = "dac"
RPC_PORT_NUMBER = 8484


def run(plan, args, contract_setup_addresses):
    db_configs = databases.get_db_configs(
        args.get("deployment_suffix"), args.get("sequencer_type")
    )
    config_artifact = plan.render_templates(
        name="cdk-data-availability-config{}".format(args.get("deployment_suffix")),
        config={
            "config.toml": struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/cdk-data-availability/config.toml"
                ),
                data={
                    "keystore_password": args.get("l2_keystore_password"),
                    "rpc_port_number": RPC_PORT_NUMBER,
                    # log
                    "log_level": args.get("log_level"),
                    "environment": args.get("environment"),
                    # layer 1
                    "l1_rpc_url": args.get("mitm_rpc_url").get(
                        "dac", args["l1_rpc_url"]
                    ),
                    "l1_ws_url": args.get("l1_ws_url"),
                }
                | contract_setup_addresses
                | db_configs,
            )
        },
    )

    keystore_artifact = plan.store_service_files(
        name="cdk-data-availability-keystore{}".format(args.get("deployment_suffix")),
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/dac.keystore",
    )

    plan.add_service(
        name="cdk-data-availability{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("cdk_data_availability_image"),
            ports={
                RPC_PORT_ID: PortSpec(RPC_PORT_NUMBER),
            },
            files={
                "/etc/cdk-data-availability": Directory(
                    artifact_names=[config_artifact, keystore_artifact]
                ),
            },
            entrypoint=[
                "/app/cdk-data-availability",
            ],
            cmd=["run", "--cfg", "/etc/cdk-data-availability/config.toml"],
        ),
    )
