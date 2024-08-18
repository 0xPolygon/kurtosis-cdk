cdk_databases_package = import_module("./cdk_databases.star")
cdk_erigon_package = import_module("./lib/cdk_erigon.star")
cdk_node_package = import_module("./lib/cdk_node.star")
data_availability_package = import_module("./lib/data_availability.star")
service_package = import_module("./lib/service.star")
zkevm_dac_package = import_module("./lib/zkevm_dac.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_pool_manager_package = import_module("./lib/zkevm_pool_manager.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_sequence_sender_package = import_module("./lib/zkevm_sequence_sender.star")


def run(plan, args):
    # Get databases.
    db_configs = cdk_databases_package.get_db_configs(
        sequencer_type=args["sequencer_type"], suffix=args["deployment_suffix"]
    )

    # Get the genesis file artifact.
    # TODO: Retrieve the genesis file artifact once it is available in Kurtosis.
    genesis_artifact = ""
    if "genesis_artifact" in args:
        genesis_artifact = args["genesis_artifact"]
    else:
        genesis_file = read_file(src=args["genesis_file"])
        genesis_artifact = plan.render_templates(
            name="genesis",
            config={"genesis.json": struct(template=genesis_file, data={})},
        )

    # Get keystores.
    keystore_artifacts = get_keystores_artifacts(plan, args)

    # Start prover.
    prover_config_template = read_file(
        src="./templates/trusted-node/prover-config.json"
    )
    prover_config_artifact = plan.render_templates(
        name="prover-config-artifact",
        config={
            "prover-config.json": struct(
                template=prover_config_template,
                data=args | db_configs,
            )
        },
    )
    zkevm_prover_package.start_prover(plan, args, prover_config_artifact)

    if args["sequencer_type"] == "zkevm":
        # Create the zkevm node config.
        node_config_template = read_file(
            src="./templates/trusted-node/node-config.toml"
        )
        node_config_artifact = plan.render_templates(
            config={
                "node-config.toml": struct(
                    template=node_config_template,
                    data=args
                    | {
                        "is_cdk_validium": data_availability_package.is_cdk_validium(
                            args
                        ),
                    }
                    | db_configs,
                )
            },
            name="trusted-node-config",
        )

        # Start the synchronizer.
        zkevm_node_package.start_synchronizer(
            plan, args, node_config_artifact, genesis_artifact
        )

        # Start the rest of the zkevm node components.
        zkevm_node_components_configs = (
            zkevm_node_package.create_zkevm_node_components_config(
                args, node_config_artifact, genesis_artifact, keystore_artifacts
            )
        )
        plan.add_services(
            configs=zkevm_node_components_configs,
            description="Starting the rest of the zkevm node components",
        )
    elif args["sequencer_type"] == "erigon":
        # Deploy CDK erigon sequencer.
        plan.print("Deploying cdk-erigon sequencer")
        cdk_erigon_package.start_sequencer(plan, args)

        # Deploy zkevm pool manager.
        zkevm_pool_manager_config_template = read_file(
            src="./templates/pool-manager/pool-manager-config.toml"
        )
        zkevm_pool_manager_config_artifact = plan.render_templates(
            name="pool-manager-config-artifact",
            config={
                "pool-manager-config.toml": struct(
                    template=zkevm_pool_manager_config_template,
                    data=args
                    | {
                        "deployment_suffix": args["deployment_suffix"],
                        "zkevm_pool_manager_port": args["zkevm_pool_manager_port"],
                        # ports
                        "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    }
                    | db_configs,
                )
            },
        )
        zkevm_pool_manager_config = (
            zkevm_pool_manager_package.create_zkevm_pool_manager_service_config(
                args, zkevm_pool_manager_config_artifact
            )
        )
        plan.add_services(
            configs=zkevm_pool_manager_config,
            description="Starting zkevm pool manager",
        )

        # Create the cdk node config.
        node_config_template = read_file(
            src="./templates/trusted-node/cdk-node-config.toml"
        )
        contract_setup_addresses = service_package.get_contract_setup_addresses(
            plan, args
        )
        node_config_artifact = plan.render_templates(
            name="cdk-node-config-artifact",
            config={
                "cdk-node-config.toml": struct(
                    template=node_config_template,
                    data=args
                    | {
                        "is_cdk_validium": data_availability_package.is_cdk_validium(
                            args
                        ),
                    }
                    | db_configs
                    | contract_setup_addresses,
                )
            },
        )

        # Start the cdk components.
        cdk_node_configs = cdk_node_package.create_cdk_node_service_config(
            args, node_config_artifact, genesis_artifact, keystore_artifacts
        )
        plan.add_services(
            configs=cdk_node_configs,
            description="Starting the cdk node components",
        )

    # Start the DAC if in validium mode.
    if data_availability_package.is_cdk_validium(args):
        dac_config_artifact = create_dac_config_artifact(plan, args, db_configs)
        dac_config = zkevm_dac_package.create_dac_service_config(
            args, dac_config_artifact, keystore_artifacts.dac
        )
        plan.add_services(
            configs=dac_config,
            description="Starting the DAC",
        )


def get_keystores_artifacts(plan, args):
    sequencer_keystore_artifact = plan.store_service_files(
        name="sequencer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/sequencer.keystore",
    )
    aggregator_keystore_artifact = plan.store_service_files(
        name="aggregator-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/aggregator.keystore",
    )
    proofsigner_keystore_artifact = plan.store_service_files(
        name="proofsigner-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/proofsigner.keystore",
    )
    dac_keystore_artifact = plan.store_service_files(
        name="dac-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/dac.keystore",
    )
    return struct(
        sequencer=sequencer_keystore_artifact,
        aggregator=aggregator_keystore_artifact,
        proofsigner=proofsigner_keystore_artifact,
        dac=dac_keystore_artifact,
    )


def create_dac_config_artifact(plan, args, db_configs):
    dac_config_template = read_file(src="./templates/trusted-node/dac-config.toml")
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    return plan.render_templates(
        name="dac-config-artifact",
        config={
            "dac-config.toml": struct(
                template=dac_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l1_ws_url": args["l1_ws_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # ports
                    "zkevm_dac_port": args["zkevm_dac_port"],
                }
                | contract_setup_addresses
                | db_configs,
            )
        },
    )
