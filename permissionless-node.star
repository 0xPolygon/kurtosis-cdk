zkevm_dbs_package = import_module("./lib/zkevm_dbs.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")


def run(plan, args):
    # Start databases.
    event_db_init_script = plan.upload_files(
        src="./templates/databases/event-db-init.sql",
        name="event-db-init.sql" + args["deployment_suffix"],
    )
    executor_db_init_script = plan.upload_files(
        src="./templates/databases/prover-db-init.sql",
        name="executor-db-init.sql" + args["deployment_suffix"],
    )
    zkevm_dbs_package.start_databases(
        plan, args, event_db_init_script, executor_db_init_script
    )

    # Start executor.
    executor_config_template = read_file(src="./templates/permissionless-node/executor-config.json")
    executor_config_artifact = plan.render_templates(
        name="executor-config",
        config={
            "executor-config.json": struct(template=executor_config_template, data=args)
        },
    )
    zkevm_prover_package.start_executor(plan, args, executor_config_artifact)

    # Start synchronizer and rpc.
    node_config_template = read_file(src="./templates/permissionless-node/node-config.toml")
    node_config_artifact = plan.render_templates(
        name="node-config",
        config={"node-config.toml": struct(template=node_config_template, data=args)},
    )
    genesis_file = read_file(src=args["genesis_file"])
    genesis_artifact = plan.render_templates(
        name="genesis", config={"genesis.json": struct(template=genesis_file, data={})}
    )
    zkevm_node_package.start_synchronizer(
        plan, args, node_config_artifact, genesis_artifact
    )
    zkevm_node_package.start_rpc(plan, args, node_config_artifact, genesis_artifact)
