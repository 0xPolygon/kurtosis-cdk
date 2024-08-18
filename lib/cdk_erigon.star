def start_sequencer(plan, args):
    cdk_erigon_node_config_template = read_file(src="./templates/cdk-erigon/config.yml")
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    cdk_erigon_node_config_artifact = plan.render_templates(
        name="cdk-erigon-node-config-artifact-sequencer",
        config={
            "config.yaml": struct(
                template=cdk_erigon_node_config_template,
                data={
                    "zkevm_data_stream_port": args["zkevm_data_streamer_port"],
                    "is_sequencer": True,
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    cdk_erigon_node_chain_spec_artifact = get_cdk_erigon_chain_spec_config(plan, args)
    cdk_erigon_node_chain_config_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-config",
    )
    cdk_erigon_node_chain_allocs_artifact = plan.get_files_artifact(
        name="cdk-erigon-node-chain-allocs",
    )

    start_cdk_erigon_node(
        plan,
        args,
        cdk_erigon_node_config_artifact,
        cdk_erigon_node_chain_spec_artifact,
        cdk_erigon_node_chain_config_artifact,
        cdk_erigon_node_chain_allocs_artifact,
        True,
    )


def start_rpc(plan, args):
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

    cdk_erigon_node_config_template = read_file(src="./templates/cdk-erigon/config.yml")
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    cdk_erigon_node_config_artifact = plan.render_templates(
        name="cdk-erigon-node-config-artifact",
        config={
            "config.yaml": struct(
                template=cdk_erigon_node_config_template,
                data={
                    "zkevm_sequencer_url": zkevm_sequence_url,
                    "zkevm_datastreamer_url": zkevm_datastreamer_url,
                    "is_sequencer": False,
                }
                | args
                | contract_setup_addresses,
            ),
        },
    )

    cdk_erigon_node_chain_spec_artifact = get_cdk_erigon_chain_spec_config(plan, args)
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


def get_cdk_erigon_chain_spec_config(plan, args):
    cdk_erigon_node_chain_spec_template = read_file(
        src="./templates/cdk-erigon/chainspec.json"
    )
    return plan.render_templates(
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


def start_cdk_erigon_node(
    plan,
    args,
    cdk_erigon_node_config_artifact,
    cdk_erigon_node_chain_spec_artifact,
    cdk_erigon_node_chain_config_artifact,
    cdk_erigon_node_chain_allocs_artifact,
    is_sequencer,
):
    envs = {"CDK_ERIGON_SEQUENCER": "1" if is_sequencer else "0"}
    ports = {}
    ports["pprof"] = PortSpec(
        args["zkevm_pprof_port"],
        application_protocol="http",
        wait=None,
    )
    ports["prometheus"] = PortSpec(
        args["zkevm_prometheus_port"],
        application_protocol="http",
        wait=None,
    )

    if is_sequencer:
        name = args["sequencer_name"] + args["deployment_suffix"]
        # TODO these port names seem weird... http-rpc / rpc? I don't
        # get it. There seem to be a bunch of weird dependencies on
        # both of these existing. It seems likt they should be called
        # the same thing and the only difference is if this a
        # sequencer or an rpc.. the port itself shouldn't be named
        # differently and there certainly shouldn't be dependencies on
        # those names
        ports["rpc"] = PortSpec(
            args["zkevm_rpc_http_port"],
            application_protocol="http",
        )
    else:
        name = args["l2_rpc_name"] + args["deployment_suffix"]
        ports["http-rpc"] = PortSpec(
            args["zkevm_rpc_http_port"],
            application_protocol="http",
        )

    if is_sequencer:
        ports["data-streamer"] = PortSpec(
            args["zkevm_data_streamer_port"], application_protocol="datastream"
        )

    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=args["cdk_erigon_node_image"],
            ports=ports,
            files={
                "/etc/cdk-erigon": Directory(
                    artifact_names=[
                        cdk_erigon_node_config_artifact,
                        cdk_erigon_node_chain_spec_artifact,
                        cdk_erigon_node_chain_config_artifact,
                        cdk_erigon_node_chain_allocs_artifact,
                    ],
                ),
                "/home/erigon/dynamic-configs/": Directory(
                    artifact_names=[
                        cdk_erigon_node_chain_spec_artifact,
                        cdk_erigon_node_chain_config_artifact,
                        cdk_erigon_node_chain_allocs_artifact,
                    ]
                ),
            },
            entrypoint=["sh", "-c"],
            # Sleep for 10 seconds in order to wait for datastream server getting ready
            # TODO: find a better way instead of waiting
            cmd=[
                "sleep 10 && cdk-erigon --pprof=true --pprof.addr 0.0.0.0 --config /etc/cdk-erigon/config.yaml"
            ],
            env_vars=envs,
        ),
    )
