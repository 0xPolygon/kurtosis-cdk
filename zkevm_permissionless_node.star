zkevm_databases_package = import_module("./lib/zkevm_databases.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")


def run(plan, args):
    # Start node databases.
    event_db_init_script = plan.upload_files(
        name="event-db-init.sql" + args["deployment_suffix"],
        src="./templates/databases/event-db-init.sql",
    )
    executor_db_init_script = plan.upload_files(
        name="executor-db-init.sql" + args["deployment_suffix"],
        src="./templates/databases/prover-db-init.sql",
    )
    node_db_configs = zkevm_databases_package.create_node_db_service_configs(
        args, event_db_init_script, executor_db_init_script
    )
    plan.add_services(
        configs=node_db_configs,
        description="Starting node databases",
    )

    # Start executor.
    executor_config_template = read_file(
        src="./templates/permissionless-node/executor-config.json"
    )
    executor_config_artifact = plan.render_templates(
        name="executor-config",
        config={
            "executor-config.json": struct(template=executor_config_template, data=args)
        },
    )
    zkevm_prover_package.start_executor(plan, args, executor_config_artifact)

    # Get the genesis file artifact.
    # TODO: Retrieve the genesis file artifact once it is available in Kurtosis.
    genesis_artifact = ""
    if "genesis_artifact" in args:
        genesis_artifact = args["genesis_artifact"]
    else:
        genesis_file = read_file(src=args["genesis_file"])
        genesis_artifact = plan.render_templates(
            name="genesis" + args["deployment_suffix"],
            config={"genesis.json": struct(template=genesis_file, data={})},
        )

    # Start zkevm synchronizer and rpc.
    node_config_template = read_file(
        src="./templates/permissionless-node/node-config.toml"
    )
    node_config_artifact = plan.render_templates(
        name="permissionless-node-config",
        config={"node-config.toml": struct(template=node_config_template, data=args)},
    )

    zkevm_node_package.start_synchronizer(
        plan, args, node_config_artifact, genesis_artifact
    )

    rpc_config = zkevm_node_package.create_rpc_service_config(
        args, node_config_artifact, genesis_artifact
    )
    plan.add_services(
        configs=rpc_config,
        description="Starting zkevm node rpc",
    )
