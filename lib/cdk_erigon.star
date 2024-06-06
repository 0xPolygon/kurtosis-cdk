def start_sequencer(
    plan,
    args,
    cdk_erigon_node_config_artifact,
    cdk_erigon_node_chain_spec_artifact,
    cdk_erigon_node_chain_config_artifact,
    cdk_erigon_node_chain_allocs_artifact,
):
    # TODO: Remove this once a version built for both amd64 and arm64 is available.
    cpu_arch_result = plan.run_sh(
        description="Determining CPU system architecture",
        run="uname -m | tr -d '\n'",
    )
    cpu_arch = cpu_arch_result.output

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
                        # TODO: There is a bug in cdk-erigon sequencer. It does not take into account datadir.
                        cdk_erigon_node_chain_spec_artifact,
                        cdk_erigon_node_chain_config_artifact,
                        cdk_erigon_node_chain_allocs_artifact,
                    ],
                ),
                # "/home/erigon/dynamic-configs/": Directory(
                #     artifact_names=[
                #         cdk_erigon_node_chain_spec_artifact,
                #         cdk_erigon_node_chain_config_artifact,
                #         cdk_erigon_node_chain_allocs_artifact,
                #     ]
                # ),
            },
            entrypoint=["/bin/bash", "-c"],  # TODO: Remove once arm64 img is available.
            # cmd=["--config=/etc/cdk-erigon/config.yaml"],
            cmd=[
                '[[ "{0}" == "aarch64" || "{0}" == "arm64" ]] && export EXPERIMENTAL_DOCKER_DESKTOP_FORCE_QEMU=1; \
                /usr/local/bin/cdk-erigon --config /etc/cdk-erigon/config.yaml'.format(
                    cpu_arch
                ),
            ],
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
