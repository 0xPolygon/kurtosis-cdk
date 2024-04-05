zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")


def run(plan, args):
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

    # Get the config and keystores.
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
    proofsigner_keystore_artifact = plan.store_service_files(
        name="proofsigner-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/proofsigner.keystore",
    )
    keystore_artifacts = struct(
        sequencer=sequencer_keystore_artifact,
        aggregator=aggregator_keystore_artifact,
        proofsigner=proofsigner_keystore_artifact,
    )

    # Start all the zkevm node components.
    synchronizer_config = zkevm_node_package.create_synchronizer_service_config(
        args, config_artifact, genesis_artifact
    )
    plan.add_service(
        config=synchronizer_config,
        description="Starting the zkevm node synchronizer",
    )

    zkevm_node_components_configs = (
        zkevm_node_package.create_zkevm_node_components_config(
            args, config_artifact, genesis_artifact, keystore_artifacts
        )
    )
    plan.add_services(
        configs=zkevm_node_components_configs,
        description="Starting the rest of the zkevm node components",
    )
