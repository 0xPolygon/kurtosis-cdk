zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
databases = import_module("./databases.star")


def run(plan, args, genesis_artifact):
    db_config = databases.get_pless_db_configs(args["original_suffix"])

    # Start executor.
    executor_config_template = read_file(
        src="./templates/permissionless-node/executor-config.json"
    )
    executor_config_artifact = plan.render_templates(
        name="executor-config",
        config={
            "executor-config.json": struct(
                template=executor_config_template, data=args | db_config
            )
        },
    )
    zkevm_prover_package.start_executor(plan, args, executor_config_artifact)

    # Get the genesis file artifact.
    # TODO: Retrieve the genesis file artifact once it is available in Kurtosis.
    if genesis_artifact == "":
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
        config={
            "node-config.toml": struct(
                template=node_config_template, data=args | db_config
            )
        },
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
