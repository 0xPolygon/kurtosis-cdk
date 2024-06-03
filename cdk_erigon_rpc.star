service_package = import_module("./lib/service.star")
cdk_erigon_package = import_module("./lib/cdk_erigon.star")


def run(plan, args):
    # Get sequencer and datastreamer urls.
    zkevm_sequencer_service = plan.get_service(
        name="zkevm-node-sequencer" + args["deployment_suffix"]
    )
    zkevm_sequence_url = "http://{}:{}".format(
        zkevm_sequencer_service.ip_address, zkevm_sequencer_service.ports["rpc"].number
    )
    zkevm_datastreamer_url = "{}:{}".format(
        zkevm_sequencer_service.ip_address,
        zkevm_sequencer_service.ports["data-streamer"].number,
    )

    # Get contract addresses.
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)

    # Create cdk-erigon rpc config.
    cdk_erigon_rpc_config_template = read_file(src="./templates/cdk-erigon/config.yaml")
    cdk_erigon_rpc_config_artifact = plan.render_templates(
        name="cdk-erigon-node-config-artifact",
        config={
            "config.yaml": struct(
                template=cdk_erigon_rpc_config_template,
                data={
                    "zkevm_sequencer_url": zkevm_sequence_url,
                    "zkevm_datastreamer_url": zkevm_datastreamer_url,
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    cdk_erigon_rpc_chain_spec_template = read_file(
        src="./templates/cdk-erigon/chainspec.json"
    )
    cdk_erigon_rpc_chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-node-chain-spec-artifact",
        config={
            "dynamic-kurtosis-chainspec.json": struct(
                template=cdk_erigon_rpc_chain_spec_template,
                data={
                    "chain_id": args["zkevm_rollup_chain_id"],
                },
            ),
        },
    )

    cdk_erigon_rpc_chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-config",
    )
    cdk_erigon_rpc_chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-allocs",
    )

    # Start cdk-erigon rpc.
    cdk_erigon_package.start_rpc(
        plan,
        args,
        cdk_erigon_rpc_config_artifact,
        cdk_erigon_rpc_chain_spec_artifact,
        cdk_erigon_rpc_chain_config_artifact,
        cdk_erigon_rpc_chain_allocs_artifact,
    )
