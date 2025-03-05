cdk_erigon_package = import_module("./lib/cdk_erigon.star")
zkevm_prover_package = import_module("./lib/zkevm_prover.star")


def run_sequencer(plan, args, contract_setup_addresses):
    # Start the zkevm stateless executor if strict mode is enabled.
    if args["erigon_strict_mode"]:
        stateless_configs = {}
        stateless_configs["stateless_executor"] = True
        stateless_executor_config_template = read_file(
            src="./templates/trusted-node/prover-config.json"
        )
        stateless_executor_config_artifact = plan.render_templates(
            name="stateless-executor-config-artifact",
            config={
                "stateless-executor-config.json": struct(
                    template=stateless_executor_config_template,
                    data=args | stateless_configs,
                )
            },
        )
        zkevm_prover_package.start_stateless_executor(
            plan,
            args,
            stateless_executor_config_artifact,
            "zkevm_stateless_executor_start_port",
        )

    cdk_erigon_config_template = read_file(src="./templates/cdk-erigon/config.yml")
    cdk_erigon_sequencer_config_artifact = plan.render_templates(
        name="cdk-erigon-sequencer-config-artifact",
        config={
            "config.yaml": struct(
                template=cdk_erigon_config_template,
                data={
                    "zkevm_data_stream_port": args["zkevm_data_streamer_port"],
                    "is_sequencer": True,
                    "consensus_contract_type": args["consensus_contract_type"],
                    "l1_sync_start_block": 1 if args["anvil_state_file"] else 0,
                    "prometheus_port": args["prometheus_port"],
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    cdk_erigon_chain_spec_template = read_file(
        src="./templates/cdk-erigon/chainspec.json"
    )
    cdk_erigon_chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-sequencer-chain-spec-artifact",
        config={
            "dynamic-"
            + args["chain_name"]
            + "-chainspec.json": struct(
                template=cdk_erigon_chain_spec_template,
                data={
                    "chain_id": args["zkevm_rollup_chain_id"],
                    "enable_normalcy": args["enable_normalcy"],
                    "chain_name": args["chain_name"],
                },
            ),
        },
    )

    cdk_erigon_chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-config",
    )
    cdk_erigon_chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-allocs",
    )
    cdk_erigon_chain_first_batch_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-first-batch",
    )

    cdk_erigon_datadir = Directory(
        persistent_key="cdk-erigon-datadir" + args["deployment_suffix"],
    )

    config_artifacts = struct(
        config=cdk_erigon_sequencer_config_artifact,
        chain_spec=cdk_erigon_chain_spec_artifact,
        chain_config=cdk_erigon_chain_config_artifact,
        chain_allocs=cdk_erigon_chain_allocs_artifact,
        chain_first_batch=cdk_erigon_chain_first_batch_artifact,
        datadir=cdk_erigon_datadir,
    )
    cdk_erigon_package.start_cdk_erigon_sequencer(
        plan, args, config_artifacts, "cdk_erigon_sequencer_start_port"
    )


def run_rpc(plan, args, contract_setup_addresses):
    zkevm_sequencer_service = plan.get_service(
        name=args["sequencer_name"] + args["deployment_suffix"]
    )
    zkevm_sequence_url = "http://{}:{}".format(
        zkevm_sequencer_service.ip_address, zkevm_sequencer_service.ports["rpc"].number
    )
    zkevm_datastreamer_url = "{}:{}".format(
        zkevm_sequencer_service.ip_address,
        zkevm_sequencer_service.ports["data-streamer"].number,
    )

    pool_manager_service = plan.get_service(
        name="zkevm-pool-manager" + args["deployment_suffix"]
    )
    pool_manager_url = "http://{}:{}".format(
        pool_manager_service.ip_address,
        pool_manager_service.ports["http"].number,
    )
    cdk_erigon_config_template = read_file(src="./templates/cdk-erigon/config.yml")
    cdk_erigon_rpc_config_artifact = plan.render_templates(
        name="cdk-erigon-rpc-config-artifact",
        config={
            "config.yaml": struct(
                template=cdk_erigon_config_template,
                data={
                    "zkevm_sequencer_url": zkevm_sequence_url,
                    "zkevm_datastreamer_url": zkevm_datastreamer_url,
                    "is_sequencer": False,
                    "pool_manager_url": pool_manager_url,
                    "consensus_contract_type": args["consensus_contract_type"],
                    "l1_sync_start_block": 0,
                    "prometheus_port": args["prometheus_port"],
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    cdk_erigon_chain_spec_template = read_file(
        src="./templates/cdk-erigon/chainspec.json"
    )
    cdk_erigon_chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-rpc-chain-spec-artifact",
        config={
            "dynamic-"
            + args["chain_name"]
            + "-chainspec.json": struct(
                template=cdk_erigon_chain_spec_template,
                data={
                    "chain_id": args["zkevm_rollup_chain_id"],
                    "enable_normalcy": args["enable_normalcy"],
                    "chain_name": args["chain_name"],
                },
            ),
        },
    )

    cdk_erigon_chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-config",
    )
    cdk_erigon_chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-allocs",
    )
    cdk_erigon_chain_first_batch_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-first-batch",
    )

    config_artifacts = struct(
        config=cdk_erigon_rpc_config_artifact,
        chain_spec=cdk_erigon_chain_spec_artifact,
        chain_config=cdk_erigon_chain_config_artifact,
        chain_allocs=cdk_erigon_chain_allocs_artifact,
        chain_first_batch=cdk_erigon_chain_first_batch_artifact,
    )
    cdk_erigon_package.start_cdk_erigon_rpc(
        plan, args, config_artifacts, "cdk_erigon_rpc_start_port"
    )
