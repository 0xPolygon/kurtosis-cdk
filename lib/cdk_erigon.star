def start_node(
    plan,
    args,
    cdk_erigon_node_config_artifact,
    cdk_erigon_node_chain_spec_artifact,
    cdk_erigon_node_chain_config_artifact,
    cdk_erigon_node_chain_allocs_artifact,
    is_sequencer
):
    envs = {"CDK_ERIGON_SEQUENCER": "1" if is_sequencer else "0"}
    ports = {}
    if is_sequencer:
        ports["rpc"] = PortSpec(args["zkevm_rpc_http_port"], application_protocol="http")
        # ports["http-rpc"] = PortSpec(8545, application_protocol="http")
        name = "cdk-erigon-sequencer" + args["deployment_suffix"]
    else:
        ports = {"http-rpc": PortSpec(8545, application_protocol="http")}
        name = "cdk-erigon-node" + args["deployment_suffix"]

    if is_sequencer:
        ports["data-streamer"] = PortSpec(args["zkevm_data_streamer_port"], application_protocol="datastream")
    
    plan.add_service(
        name=name,
        config=ServiceConfig(
            image="cdk-erigon:local",
            ports=ports,
            files={
                "/etc/cdk-erigon": Directory(
                    artifact_names=[
                        cdk_erigon_node_config_artifact,
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
            cmd=["--config=/etc/cdk-erigon/config.yaml"],
            env_vars=envs,
        ),
    )
