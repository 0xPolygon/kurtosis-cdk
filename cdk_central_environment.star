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
    sequence_sender_aggregator_type = args["sequence_sender_aggregator_type"]

    db_configs = databases.get_db_configs(
        args["deployment_suffix"], sequencer_type, sequence_sender_aggregator_type
    )

    # Start prover.
    prover_config_template = read_file(
        src="./templates/trusted-node/zkevm-prover-config.json"
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
        sequence_sender_aggregator_type
        == constants.SEQUENCE_SENDER_AGGREGATOR_TYPE.zkevm
    ):
        zkevm_node_config_artifact = create_zkevm_node_config_artifact(
            plan, args, db_configs
        )

    # Deploy sequencer and rpc.
    if sequencer_type == constants.SEQUENCER_TYPE.erigon:
        run_erigon_sequencer(plan, args, db_configs)
    elif sequencer_type == constants.SEQUENCER_TYPE.zkevm:
        zkevm_node_package.run_synchronizer(
            plan, args, zkevm_node_config_artifact, genesis_artifact
        )
        zkevm_node_package.run_sequencer(
            plan, args, zkevm_node_config_artifact, genesis_artifact, keystore_artifacts
        )
        zkevm_node_package.run_rpc(
            plan, args, zkevm_node_config_artifact, genesis_artifact
        )
    else:
        fail("Unsupported sequencer type: '{}'".format(sequencer_type))

    # Deploy aggregator and sequence sender.
    if sequence_sender_aggregator_type == constants.SEQUENCE_SENDER_AGGREGATOR_TYPE.cdk:
        cdk_node_config_artifact = create_cdk_node_config_artifact(
            plan, args, db_configs
        )
        cdk_node_package.run_aggregator_and_sequence_sender(
            plan, args, cdk_node_config_artifact, genesis_artifact, keystore_artifacts
        )
    elif (
        sequence_sender_aggregator_type
        == constants.SEQUENCE_SENDER_AGGREGATOR_TYPE.zkevm
    ):
        # Then start the aggregator and the sequence sender.
        zkevm_sequence_sender_config_artifact = (
            create_zkevm_sequence_sender_config_artifact(plan, args)
        )
        zkevm_sequence_sender_service_config = (
            zkevm_sequence_sender_package.create_zkevm_sequence_sender_config(
                args,
                zkevm_sequence_sender_config_artifact,
                genesis_artifact,
                keystore_artifacts.sequencer,
            )
        )

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
        plan.add_services(
            configs=zkevm_sequence_sender_service_config
            | zkevm_aggregator_service_config,
            description="Starting zkevm sequence sender and aggregator",
        )
    else:
        fail(
            "Unsupported sequence sender and aggregator type: '{}'".format(
                sequence_sender_aggregator_type
            )
        )

    # If in cdk-validium mode, deploy the data availability comitee.
    if data_availability_package.is_cdk_validium(args):
        dac_config_artifact = create_dac_config_artifact(plan, args, db_configs)
        dac_config = zkevm_dac_package.create_dac_service_config(
            args, dac_config_artifact, keystore_artifacts.dac
        )
        plan.add_services(
            configs=dac_config,
            description="Starting cdk-validium data availability comitee",
        )


def run_erigon_sequencer(plan, args, db_configs):
    cdk_erigon_sequencer_config_artifact = create_cdk_erigon_sequencer_artifact(
        plan, args
    )
    cdk_erigon_chain_artifacts = create_cdk_erigon_chain_artifacts(plan, args)
    cdk_erigon_package.run_sequencer(
        plan,
        args,
        cdk_erigon_sequencer_config_artifact,
        cdk_erigon_chain_artifacts,
    )

    cdk_erigon_rpc_config_artifact = create_cdk_erigon_rpc_artifact(plan, args)
    zkevm_pool_manager_config_artifact = create_zkevm_pool_manager_config_artifact(
        plan, args, db_configs
    )
    cdk_erigon_package.run_rpc(
        plan,
        args,
        cdk_erigon_rpc_config_artifact,
        cdk_erigon_chain_artifacts,
        zkevm_pool_manager_config_artifact,
    )

    if args["erigon_strict_mode"]:
        stateless_executor_config_artifact = plan.render_templates(
            name="stateless-executor-config-artifact",
            config={
                "stateless-executor-config.json": struct(
                    template=read_file(
                        src="./templates/trusted-node/zkevm-prover-config.json"
                    ),
                    data=args | {"stateless_executor": True},
                )
            },
        )
        zkevm_prover_package.start_stateless_executor(
            plan, args, stateless_executor_config_artifact
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
        src="./templates/trusted-node/zkevm-node-config.toml"
    )
    return plan.render_templates(
        config={
            "node-config.toml": struct(
                template=zkevm_node_config_template,
                data=args
                | db_configs
                | {
                    "is_cdk_validium": data_availability_package.is_cdk_validium(args),
                },
            )
        },
        name="trusted-node-config",
    )


def create_zkevm_sequence_sender_config_artifact(plan, args):
    sequence_sender_config_template = read_file(
        src="./templates/trusted-node/sequence-sender-config.toml"
    )
    return plan.render_templates(
        name="zkevm-sequence-sender-config-artifact",
        config={
            "sequence-sender-config.toml": struct(
                data=args
                | {
                    "zkevm_is_validium": data_availability_package.is_cdk_validium(
                        args
                    ),
                },
                template=sequence_sender_config_template,
            ),
        },
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


def create_cdk_erigon_sequencer_artifact(plan, args):
    node_config_template = read_file(src="./templates/cdk-erigon/config.yml")
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    return plan.render_templates(
        name="cdk-erigon-sequencer-config-artifact",
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


def create_cdk_erigon_rpc_artifact(plan, args):
    node_config_template = read_file(src="./templates/cdk-erigon/config.yml")
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    sequencer_service = plan.get_service(
        name=args["sequencer_name"] + args["deployment_suffix"]
    )
    sequencer_url = "http://{}:{}".format(
        sequencer_service.ip_address, sequencer_service.ports["http-rpc"].number
    )
    datastreamer_url = "{}:{}".format(
        sequencer_service.ip_address,
        sequencer_service.ports["data-streamer"].number,
    )
    return plan.render_templates(
        name="cdk-erigon-rpc-config-artifact",
        config={
            "config.yaml": struct(
                template=node_config_template,
                data={
                    "sequencer_url": sequencer_url,
                    "datastreamer_url": datastreamer_url,
                    "is_sequencer": False,
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )


def create_cdk_erigon_chain_artifacts(plan, args):
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
        spec=chain_spec_artifact,
        config=chain_config_artifact,
        allocs=chain_allocs_artifact,
    )


def create_zkevm_pool_manager_config_artifact(plan, args, db_configs):
    zkevm_pool_manager_config_template = read_file(
        src="./templates/pool-manager/pool-manager-config.toml"
    )
    return plan.render_templates(
        name="pool-manager-config-artifact",
        config={
            "pool-manager-config.toml": struct(
                template=zkevm_pool_manager_config_template,
                data=args
                | {
                    "deployment_suffix": args["deployment_suffix"],
                    "zkevm_pool_manager_port": args["zkevm_pool_manager_port"],
                    # ports
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                }
                | db_configs,
            )
        },
    )


def create_dac_config_artifact(plan, args, db_configs):
    dac_config_template = read_file(src="./templates/trusted-node/cdk-dac-config.toml")
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
