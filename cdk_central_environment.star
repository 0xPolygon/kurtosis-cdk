zkevm_databases_package = import_module("./lib/zkevm_databases.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")


def run(plan, args):
    # Start databases
    event_db_init_script = plan.upload_files(
        src="./templates/databases/event-db-init.sql",
        name="event-db-init.sql" + args["deployment_suffix"],
    )
    prover_db_init_script = plan.upload_files(
        src="./templates/databases/prover-db-init.sql",
        name="prover-db-init.sql" + args["deployment_suffix"],
    )
    zkevm_databases_package.start_node_databases(
        plan, args, event_db_init_script, prover_db_init_script
    )
    zkevm_databases_package.start_peripheral_databases(plan, args)

    # Start prover
    prover_config_template = read_file(
        src="./templates/trusted-node/prover-config.json"
    )
    prover_config_artifact = plan.render_templates(
        config={
            "prover-config.json": struct(template=prover_config_template, data=args)
        },
        name="prover-config-artifact",
    )
    zkevm_prover_package.start_prover(plan, args, prover_config_artifact)

    # Start the zkevm node components
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
    start_node_components(
        plan,
        args,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )


def start_node_components(
    plan,
    args,
    genesis_artifact,
    sequencer_keystore_artifact,
    aggregator_keystore_artifact,
):
    # Create node configuration file.
    config_template = read_file(src="./templates/trusted-node/node-config.toml")
    config_artifact = plan.render_templates(
        config={"node-config.toml": struct(template=config_template, data=args)},
        name="trusted-node-config",
    )

    # Deploy components.
    service_map = {}
    service_map["synchronizer"] = zkevm_node_package.start_synchronizer(
        plan, args, config_artifact, genesis_artifact
    )
    service_map["sequencer"] = zkevm_node_package.start_sequencer(
        plan, args, config_artifact, genesis_artifact
    )
    service_map["sequence_sender"] = zkevm_node_package.start_sequence_sender(
        plan, args, config_artifact, genesis_artifact, sequencer_keystore_artifact
    )
    service_map["start_aggregator"] = zkevm_node_package.start_aggregator(
        plan,
        args,
        config_artifact,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )
    service_map["rpc"] = zkevm_node_package.start_rpc(
        plan, args, config_artifact, genesis_artifact
    )

    service_map["eth_tx_manager"] = zkevm_node_package.start_eth_tx_manager(
        plan,
        args,
        config_artifact,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )

    service_map["l2_gas_pricer"] = zkevm_node_package.start_l2_gas_pricer(
        plan, args, config_artifact, genesis_artifact
    )
    return service_map
