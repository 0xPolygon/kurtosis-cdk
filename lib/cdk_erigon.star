def start_node(
    plan,
    args,
    cdk_erigon_node_config_artifact,
    cdk_erigon_node_chain_spec_artifact,
    cdk_erigon_node_chain_config_artifact,
    cdk_erigon_node_chain_allocs_artifact,
):
    plan.add_service(
        name="cdk-erigon-node" + args["deployment_suffix"],
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
