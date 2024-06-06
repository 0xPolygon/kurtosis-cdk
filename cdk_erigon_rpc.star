service_package = import_module("./lib/service.star")
cdk_erigon_package = import_module("./lib/cdk_erigon.star")


def run(plan, args):
    # Generate cdk-erigon dynamic config.
    [
        cdk_erigon_chain_spec_artifact,
        cdk_erigon_chain_config_artifact,
        cdk_erigon_chain_allocs_artifact,
    ] = _generate_dynamic_config(plan, args)

    # Start cdk-erigon rpc.
    cdk_erigon_config_template = read_file(src="./templates/cdk-erigon/config.yaml")
    cdk_erigon_rpc_config_artifact = plan.render_templates(
        name="cdk-erigon-rpc-config-artifact" + args["deployment_suffix"],
        config={
            "config.yaml": struct(
                template=cdk_erigon_config_template,
                data={
                    "zkevm_sequencer_url": args["zkevm_rpc_url"],
                    "zkevm_datastreamer_url": args["datastreamer_rpc_url"],
                }
                | args,
            ),
        },
    )
    cdk_erigon_package.start_rpc(
        plan,
        args,
        cdk_erigon_rpc_config_artifact,
        cdk_erigon_chain_spec_artifact,
        cdk_erigon_chain_config_artifact,
        cdk_erigon_chain_allocs_artifact,
    )


def _generate_dynamic_config(plan, args):
    # chainspec.json
    cdk_erigon_rpc_chain_spec_template = read_file(
        src="./templates/cdk-erigon/chainspec.json"
    )
    cdk_erigon_rpc_chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-node-chain-spec-artifact" + args["deployment_suffix"],
        config={
            "dynamic-kurtosis-chainspec.json": struct(
                template=cdk_erigon_rpc_chain_spec_template,
                data={
                    "chain_id": args["zkevm_rollup_chain_id"],
                },
            ),
        },
    )

    # conf.json
    cdk_erigon_rpc_chain_config_file = read_file(
        src=args["cdk_erigon_rpc_chain_config_file"]
    )
    cdk_erigon_rpc_chain_config_artifact = plan.render_templates(
        name="cdk-erigon-node-chain-config" + args["deployment_suffix"],
        config={
            "dynamic-kurtosis-conf.json": struct(
                template=cdk_erigon_rpc_chain_config_file, data={}
            )
        },
    )

    # allocs.json
    cdk_erigon_rpc_chain_allocs_file = read_file(
        src=args["cdk_erigon_rpc_chain_allocs_file"]
    )
    cdk_erigon_rpc_chain_allocs_artifact = plan.render_templates(
        name="cdk-erigon-node-chain-allocs" + args["deployment_suffix"],
        config={
            "dynamic-kurtosis-allocs.json": struct(
                template=cdk_erigon_rpc_chain_allocs_file, data={}
            )
        },
    )

    return [
        cdk_erigon_rpc_chain_spec_artifact,
        cdk_erigon_rpc_chain_config_artifact,
        cdk_erigon_rpc_chain_allocs_artifact,
    ]
