def start_sequencer(
    plan,
    args,
    cdk_erigon_node_config_artifact,
    cdk_erigon_node_chain_spec_artifact,
    cdk_erigon_node_chain_config_artifact,
    cdk_erigon_node_chain_allocs_artifact,
):
    return plan.add_service(
        name="cdk-erigon-sequencer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["cdk_erigon_node_image"],
            ports={
                "rpc": PortSpec(8123, application_protocol="http"),
                "data-streamer": PortSpec(6900, application_protocol="datastream"),
            },
            env_vars={
                "CDK_ERIGON_SEQUENCER": "1",
            },
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
        ),
    )


def start_rpc(
    plan,
    args,
    cdk_erigon_node_config_artifact,
    cdk_erigon_node_chain_spec_artifact,
    cdk_erigon_node_chain_config_artifact,
    cdk_erigon_node_chain_allocs_artifact,
):
    plan.add_service(
        name="cdk-erigon-rpc" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["cdk_erigon_node_image"],
            ports={
                "rpc": PortSpec(8545, application_protocol="http"),
            },
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
        ),
    )
