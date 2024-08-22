cdk_erigon_package = import_module("./lib/cdk_erigon.star")
cdk_node_package = import_module("./lib/cdk_node.star")
constants = import_module("./src/package_io/constants.star")
data_availability_package = import_module("./lib/data_availability.star")
databases = import_module("./databases.star")
service_package = import_module("./lib/service.star")
zkevm_dac_package = import_module("./lib/zkevm_dac.star")
zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")
zkevm_sequence_sender_package = import_module("./lib/zkevm_sequence_sender.star")


def run(plan, args):
    sequencer_type = args["sequencer_type"]
    aggregator_sequence_sender_type = args["aggregator_sequence_sender_type"]

    db_configs = databases.get_db_configs(args["deployment_suffix"], sequencer_type)

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

    keystore_artifacts = get_keystores_artifacts(plan, args)

    # Create zkevm-node configuration if needed.
    # It can be used by both the sequencer, the aggregator and the sequence sender.
    if (sequencer_type == constants.SEQUENCER_TYPE.zkevm) or (
        aggregator_sequence_sender_type
        == constants.AGGREGATOR_SEQUENCE_SENDER_TYPE.zkevm
    ):
        zkevm_node_config_artifact = create_zkevm_node_config_artifact(
            plan, args, db_configs
        )

    # Deploy sequencer.
    if sequencer_type == constants.SEQUENCER_TYPE.zkevm:
        zkevm_node_package.run_sequencer(
            plan, args, zkevm_node_config_artifact, genesis_artifact, keystore_artifacts
        )
    elif sequencer_type == constants.SEQUENCER_TYPE.erigon:
        cdk_erigon_node_artifacts = create_cdk_erigon_node_artifacts(plan, args)
        cdk_erigon_package.run_sequencer(
            plan,
            args,
            cdk_erigon_node_artifacts.node_config,
            cdk_erigon_node_artifacts.chain_spec,
            cdk_erigon_node_artifacts.chain_config,
            cdk_erigon_node_artifacts.chain_allocs,
        )
    else:
        fail("Unsupported sequencer type: '{}'".format(sequencer_type))

    # Deploy aggregator and sequence sender.
    if aggregator_sequence_sender_type == constants.AGGREGATOR_SEQUENCE_SENDER_TYPE.cdk:
        cdk_node_config_artifact = create_cdk_node_config_artifact(
            plan, args, db_configs
        )
        cdk_node_package.run_aggregator_and_sequence_sender(
            args, cdk_node_config_artifact, genesis_artifact, keystore_artifacts
        )
    elif (
        aggregator_sequence_sender_type
        == constants.AGGREGATOR_SEQUENCE_SENDER_TYPE.zkevm
    ):
        zkevm_aggregator_service_config = (
            zkevm_node_package.create_aggregator_service_config(
                args,
                zkevm_node_config_artifact,
                genesis_artifact,
                keystore_artifacts.sequencer,
                keystore_artifacts.aggregator,
                keystore_artifacts.proofsigner,
            )
        )
        zkevm_sequence_sender_service_config = (
            zkevm_node_package.create_sequence_sender_service_config(
                args,
                zkevm_node_config_artifact,
                genesis_artifact,
                keystore_artifacts.sequencer,
            )
        )
        plan.add_services(
            configs=zkevm_aggregator_service_config
            | zkevm_sequence_sender_service_config,
            description="Starting zkevm aggregator and sequence sender",
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


def create_zkevm_node_config_artifact(plan, args, db_configs):
    zkevm_node_config_template = read_file(
        src="./templates/trusted-node/node-config.toml"
    )
    return plan.render_templates(
        config={
            "node-config.toml": struct(
                template=zkevm_node_config_template,
                data=args
                | {
                    "is_cdk_validium": data_availability_package.is_cdk_validium(args),
                }
                | db_configs,
            )
        },
        name="trusted-node-config",
    )


def create_cdk_node_config_artifact(plan, args, db_configs):
    cdk_node_config_template = read_file(
        src="./templates/trusted-node/cdk-node-config.toml"
    )
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    return plan.render_templates(
        name="cdk-node-config-artifact",
        config={
            "cdk-node-config.toml": struct(
                template=cdk_node_config_template,
                data=args
                | {
                    "is_cdk_validium": data_availability_package.is_cdk_validium(args),
                }
                | db_configs
                | contract_setup_addresses,
            )
        },
    )


def create_cdk_erigon_node_artifacts(plan, args):
    node_config_template = read_file(src="./templates/cdk-erigon/config.yml")
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    node_config_artifact = plan.render_templates(
        name="cdk-erigon-node-config-artifact-sequencer",
        config={
            "config.yaml": struct(
                template=node_config_template,
                data={
                    "zkevm_data_stream_port": args["zkevm_data_streamer_port"],
                    "is_sequencer": True,
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    chain_spec_template = read_file(src="./templates/cdk-erigon/chainspec.json")
    chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-node-chain-spec-artifact-sequencer",
        config={
            "dynamic-kurtosis-chainspec.json": struct(
                template=chain_spec_template,
                data={
                    "chain_id": args["zkevm_rollup_chain_id"],
                },
            ),
        },
    )

    chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-config",
    )
    chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-allocs",
    )
    return struct(
        node_config=node_config_artifact,
        chain_spec=chain_spec_artifact,
        chain_config=chain_config_artifact,
        chain_allocs=chain_allocs_artifact,
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
                    "global_log_level": args["global_log_level"],
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
