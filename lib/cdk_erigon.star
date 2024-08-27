def start_node(
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
                "sleep 10 && cdk-erigon --pprof=true --pprof.addr 0.0.0.0 --config /etc/cdk-erigon/config.yaml & tail -f /dev/null"
            ],
            env_vars=envs,
        ),
    )
