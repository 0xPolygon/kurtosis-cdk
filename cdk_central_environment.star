zkevm_databases_package = import_module("./lib/zkevm_databases.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")


def run(plan, args):
    # Start node and peripheral databases.
    event_db_init_script = plan.upload_files(
        name="event-db-init.sql" + args["deployment_suffix"],
        src="./templates/databases/event-db-init.sql",
    )
    prover_db_init_script = plan.upload_files(
        name="prover-db-init.sql" + args["deployment_suffix"],
        src="./templates/databases/prover-db-init.sql",
    )
    zkevm_databases_package.start_node_databases(
        plan, args, event_db_init_script, prover_db_init_script
    )
    zkevm_databases_package.start_peripheral_databases(plan, args)

    # Start prover.
    prover_config_template = read_file(
        src="./templates/trusted-node/prover-config.json"
    )
    prover_config_artifact = plan.render_templates(
        name="prover-config-artifact",
        config={
            "prover-config.json": struct(template=prover_config_template, data=args)
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

    # Start all the zkevm node components.
    config_template = read_file(src="./templates/trusted-node/node-config.toml")
    config_artifact = plan.render_templates(
        config={"node-config.toml": struct(template=config_template, data=args)},
        name="trusted-node-config",
    )

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

    zkevm_node_package.start_synchronizer(plan, args, config_artifact, genesis_artifact)
    zkevm_node_package.start_sequencer(plan, args, config_artifact, genesis_artifact)
    zkevm_node_package.start_sequence_sender(
        plan, args, config_artifact, genesis_artifact, sequencer_keystore_artifact
    )
    zkevm_node_package.start_aggregator(
        plan,
        args,
        config_artifact,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )
    zkevm_node_package.start_rpc(plan, args, config_artifact, genesis_artifact)
    zkevm_node_package.start_eth_tx_manager(
        plan,
        args,
        config_artifact,
        genesis_artifact,
        sequencer_keystore_artifact,
        aggregator_keystore_artifact,
    )
    zkevm_node_package.start_l2_gas_pricer(
        plan, args, config_artifact, genesis_artifact
    )
