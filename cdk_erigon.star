service_package = import_module("./lib/service.star")
cdk_erigon_package = import_module("./lib/cdk_erigon.star")


def run_rpc(plan, args):
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

    cdk_erigon_node_config_template = read_file(
        src="./templates/cdk-erigon/config.yaml"
    )
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    cdk_erigon_node_config_artifact = plan.render_templates(
        name="cdk-erigon-node-config-artifact",
        config={
            "config.yaml": struct(
                template=cdk_erigon_node_config_template,
                data={
                    "zkevm_sequencer_url": zkevm_sequence_url,
                    "zkevm_datastreamer_url": zkevm_datastreamer_url,
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    cdk_erigon_node_chain_spec_template = read_file(
        src="./templates/cdk-erigon/chainspec.json"
    )
    cdk_erigon_node_chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-node-chain-spec-artifact",
        config={
            "dynamic-kurtosis-chainspec.json": struct(
                template=cdk_erigon_node_chain_spec_template,
                data={
                    "chain_id": args["zkevm_rollup_chain_id"],
                },
            ),
        },
    )

    cdk_erigon_node_chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-config",
    )
    cdk_erigon_node_chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-allocs",
    )

    cdk_erigon_package.start_node(
        plan,
        args,
        cdk_erigon_node_config_artifact,
        cdk_erigon_node_chain_spec_artifact,
        cdk_erigon_node_chain_config_artifact,
        cdk_erigon_node_chain_allocs_artifact,
        False,
    )


def run_sequencer(plan, args):
    cdk_erigon_node_config_template = read_file(
        src="./templates/cdk-erigon/config-sequencer.yaml"
    )
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    cdk_erigon_node_config_artifact = plan.render_templates(
        name="cdk-erigon-node-config-artifact-sequencer",
        config={
            "config.yaml": struct(
                template=cdk_erigon_node_config_template,
                data={
                    "zkevm_data_stream_port": args["zkevm_data_streamer_port"],
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    cdk_erigon_node_chain_spec_template = read_file(
        src="./templates/cdk-erigon/chainspec.json"
    )
    cdk_erigon_node_chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-node-chain-spec-artifact-sequencer",
        config={
            "dynamic-kurtosis-chainspec.json": struct(
                template=cdk_erigon_node_chain_spec_template,
                data={
                    "chain_id": args["zkevm_rollup_chain_id"],
                },
            ),
        },
    )

    cdk_erigon_node_chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-config",
    )
    cdk_erigon_node_chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-allocs",
    )

    cdk_erigon_package.start_node(
        plan,
        args,
        cdk_erigon_node_config_artifact,
        cdk_erigon_node_chain_spec_artifact,
        cdk_erigon_node_chain_config_artifact,
        cdk_erigon_node_chain_allocs_artifact,
        True,
    )
