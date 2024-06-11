service_package = import_module("./lib/service.star")
sequencer_package = import_module("./lib/sequencer.star")


def start_rpc(plan, args):
    _start_node(
        plan=plan,
        args=args,
        name="cdk-erigon-rpc" + args["deployment_suffix"],
        ports={
            "rpc": PortSpec(args["zkevm_rpc_http_port"], application_protocol="http"),
        },
        env_vars={},
    )


def start_sequencer(plan, args):
    _start_node(
        plan=plan,
        args=args,
        name="cdk-erigon-sequencer" + args["deployment_suffix"],
        ports={
            "rpc": PortSpec(args["zkevm_rpc_http_port"], application_protocol="http"),
            "data-streamer": PortSpec(
                args["zkevm_data_streamer_port"], application_protocol="datastream"
            ),
        },
        env_vars={"CDK_ERIGON_SEQUENCER": "1"},
    )


def _create_config(plan, args):
    # node config
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    data = args | contract_setup_addresses
    if sequencer_package.is_cdk_erigon_sequencer(args):
        data["zkevm_data_stream_port"] = args["zkevm_data_streamer_port"]
    else:
        sequencer_rpc_url = sequencer_package.get_sequencer_rpc_url(plan, args)
        data["zkevm_sequencer_url"] = sequencer_rpc_url

        zkevm_datastreamer_url = "{}:{}".format(
            zkevm_sequencer_service.ip_address,
            zkevm_sequencer_service.ports["data-streamer"].number,
        )
        data["zkevm_datastreamer_url"] = zkevm_datastreamer_url

    node_config_template = read_file(src="../templates/cdk-erigon/config.yaml")
    node_config_artifact = plan.render_templates(
        name="cdk-erigon-node-config",
        config={
            "config.yaml": struct(
                template=node_config_template,
                data=data,
            ),
        },
    )

    # chain spec
    chain_spec_template = read_file(src="../templates/cdk-erigon/chainspec.json")
    chain_spec_artifact = plan.render_templates(
        name="cdk-erigon-chain-spec",
        config={
            "dynamic-kurtosis-chainspec.json": struct(
                template=chain_spec_template,
                data={
                    "chain_id": args["zkevm_rollup_chain_id"],
                },
            ),
        },
    )

    # chain config
    chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-config",
    )

    # chain allocs
    chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-chain-allocs",
    )
    return [
        node_config_artifact,
        chain_spec_artifact,
        chain_config_artifact,
        chain_allocs_artifact,
    ]


def _start_node(plan, args, name, ports, env_vars):
    [
        node_config_artifact,
        chain_spec_artifact,
        chain_config_artifact,
        chain_allocs_artifact,
    ] = _create_config(plan, args)

    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=args["cdk_erigon_node_image"],
            ports=ports,
            files={
                "/etc/cdk-erigon": Directory(
                    artifact_names=[
                        node_config_artifact,
                        chain_spec_artifact,
                        chain_config_artifact,
                        chain_allocs_artifact,
                    ],
                ),
                "/home/erigon/dynamic-configs/": Directory(
                    artifact_names=[
                        chain_spec_artifact,
                        chain_config_artifact,
                        chain_allocs_artifact,
                    ]
                ),
            },
            env_vars=env_vars,
            entrypoint=["sh", "-c"],
            # Sleep for 10 seconds in order to wait for datastream server getting ready
            # TODO: Find a better way instead of waiting.
            cmd=["sleep 10 && cdk-erigon --config /etc/cdk-erigon/config.yaml"],
            # cmd=["--config=/etc/cdk-erigon/config.yaml"],
        ),
    )
