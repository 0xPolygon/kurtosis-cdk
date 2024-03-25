zkevm_databases_package = import_module("./lib/zkevm_databases.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")


def run(plan, args):
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
            "executor-config.json": struct(
                template=executor_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "zkevm_aggregator_host": args["zkevm_aggregator_host"],
                    # prover db
                    "zkevm_db_prover_hostname": args["zkevm_db_prover_hostname"],
                    "zkevm_db_prover_name": args["zkevm_db_prover_name"],
                    "zkevm_db_prover_user": args["zkevm_db_prover_user"],
                    "zkevm_db_prover_password": args["zkevm_db_prover_password"],
                    # ports
                    "zkevm_aggregator_port": args["zkevm_aggregator_port"],
                    "zkevm_executor_port": args["zkevm_executor_port"],
                    "zkevm_hash_db_port": args["zkevm_hash_db_port"],
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                },
            )
        },
    )
    zkevm_prover_package.start_executor(plan, args, executor_config_artifact)

    # Start synchronizer and rpc.
    node_config_template = read_file(
        src="./templates/permissionless-node/node-config.toml"
    )
    node_config_artifact = plan.render_templates(
        name="permissionless-node-config",
        config={
            "node-config.toml": struct(
                template=node_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    # state db
                    "zkevm_db_state_hostname": args["zkevm_db_state_hostname"],
                    "zkevm_db_state_name": args["zkevm_db_state_name"],
                    "zkevm_db_state_user": args["zkevm_db_state_user"],
                    "zkevm_db_state_password": args["zkevm_db_state_password"],
                    # pool db
                    "zkevm_db_pool_hostname": args["zkevm_db_pool_hostname"],
                    "zkevm_db_pool_name": args["zkevm_db_pool_name"],
                    "zkevm_db_pool_user": args["zkevm_db_pool_user"],
                    "zkevm_db_pool_password": args["zkevm_db_pool_password"],
                    # executor db
                    "zkevm_db_executor_hostname": args["zkevm_db_prover_hostname"],
                    "zkevm_db_executor_name": args["zkevm_db_prover_name"],
                    "zkevm_db_executor_user": args["zkevm_db_prover_user"],
                    "zkevm_db_executor_password": args["zkevm_db_prover_password"],
                    # event db
                    "zkevm_db_event_hostname": args["zkevm_db_event_hostname"],
                    "zkevm_db_event_name": args["zkevm_db_event_name"],
                    "zkevm_db_event_user": args["zkevm_db_event_user"],
                    "zkevm_db_event_password": args["zkevm_db_event_password"],
                    # ports
                    "zkevm_hash_db_port": args["zkevm_hash_db_port"],
                    "zkevm_executor_port": args["zkevm_executor_port"],
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "zkevm_rpc_ws_port": args["zkevm_rpc_ws_port"],
                    "zkevm_prometheus_port": args["zkevm_prometheus_port"],
                    "zkevm_pprof_port": args["zkevm_pprof_port"],
                    # permissionless node
                    "trusted_sequencer_node_uri": args["trusted_sequencer_node_uri"],
                },
            )
        },
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

    zkevm_node_package.start_synchronizer(
        plan, args, node_config_artifact, genesis_artifact
    )
    zkevm_node_package.start_rpc(plan, args, node_config_artifact, genesis_artifact)
