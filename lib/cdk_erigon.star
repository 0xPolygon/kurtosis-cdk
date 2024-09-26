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
        args["prometheus_port"],
        application_protocol="http",
        wait=None,
    )
    ports["rpc"] = PortSpec(
        args["zkevm_rpc_http_port"],
        application_protocol="http",
    )

    ports["ws-rpc"] = PortSpec(
        args["zkevm_rpc_http_port"],
        application_protocol="ws",
    )

    if is_sequencer:
        name = args["sequencer_name"] + args["deployment_suffix"]
    else:
        name = args["l2_rpc_name"] + args["deployment_suffix"]

    if is_sequencer:
        ports["data-streamer"] = PortSpec(
            args["zkevm_data_streamer_port"], application_protocol="datastream"
        )

    proc_runner_file_artifact = plan.upload_files(
        src="../templates/proc-runner.sh",
        # leaving the name out for now. This might cause some idempotency issues, but we're not currently relying on that for now
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
                "/usr/local/share/proc-runner": proc_runner_file_artifact,
            },
            entrypoint=["/usr/local/share/proc-runner/proc-runner.sh"],
            cmd=[
                "cdk-erigon --pprof=true --pprof.addr 0.0.0.0 --config /etc/cdk-erigon/config.yaml"
            ],
            env_vars=envs,
        ),
    )
