zkevm_databases_package = import_module("./lib/zkevm_databases.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
observability_package = import_module("./lib/observability.star")


def run(plan, args, run_observability=True):
    # Start node databases.
    event_db_init_script = plan.upload_files(
        src="./templates/databases/event-db-init.sql",
        name="event-db-init.sql" + args["deployment_suffix"],
    )
    executor_db_init_script = plan.upload_files(
        src="./templates/databases/prover-db-init.sql",
        name="executor-db-init.sql" + args["deployment_suffix"],
    )
    zkevm_databases_package.start_node_databases(
        plan, args, event_db_init_script, executor_db_init_script
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

    # Start synchronizer and rpc.
    node_config_template = read_file(
        src="./templates/permissionless-node/node-config.toml"
    )
    node_config_artifact = plan.render_templates(
        name="permissionless-node-config",
        config={"node-config.toml": struct(template=node_config_template, data=args)},
    )

    genesis_artifact = ""
    if "genesis_artifact" in args:
        genesis_artifact = args["genesis_artifact"]
    else:
        genesis_file = read_file(src=args["genesis_file"])
        genesis_artifact = plan.render_templates(
            name="genesis",
            config={"genesis.json": struct(template=genesis_file, data={})},
        )

    synchronizer = zkevm_node_package.start_synchronizer(
        plan, args, node_config_artifact, genesis_artifact
    )
    rpc = zkevm_node_package.start_rpc(
        plan, args, node_config_artifact, genesis_artifact
    )

    services = [synchronizer, rpc]

    if run_observability:
        observability_package.run(plan, args, services, run_panoptichain=False)

    return services
