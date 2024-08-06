data_availability_package = import_module("./lib/data_availability.star")
service_package = import_module("./lib/service.star")
zkevm_dac_package = import_module("./lib/zkevm_dac.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_sequence_sender_package = import_module("./lib/zkevm_sequence_sender.star")
databases = import_module("./databases.star")


def run(plan, args):
    db_configs = databases.get_db_configs(args["deployment_suffix"])
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

    # Create the zkevm node config.
    node_config_template = read_file(src="./templates/trusted-node/node-config.toml")
    node_config_artifact = plan.render_templates(
        config={
            "node-config.toml": struct(
                template=node_config_template,
                data=args
                | {
                    "is_cdk_validium": data_availability_package.is_cdk_validium(args),
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
    keystore_artifacts = get_keystores_artifacts(plan, args)
    zkevm_node_components_configs = (
        zkevm_node_package.create_zkevm_node_components_config(
            args, node_config_artifact, genesis_artifact, keystore_artifacts
        )
    )

    plan.add_services(
        configs=zkevm_node_components_configs,
        description="Starting the rest of the zkevm node components",
    )

    if args["sequencer_type"] == "erigon":
        sequence_sender_config = (
            zkevm_sequence_sender_package.create_zkevm_sequence_sender_config(
                plan, args, genesis_artifact, keystore_artifacts.sequencer
            )
        )

        plan.add_services(
            configs=sequence_sender_config,
            description="Starting the rest of the zkevm node components",
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
