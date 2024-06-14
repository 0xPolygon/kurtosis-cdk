service_package = import_module("./service.star")
sequencer_package = import_module("./sequencer.star")


def start_sequencer(
    plan,
    args,
    node_config_artifact,
    chain_spec_artifact,
    chain_config_artifact,
    chain_allocs_artifact,
):
    _start_node(
        plan=plan,
        args=args,
        name="cdk-erigon-sequencer" + args["deployment_suffix"],
        ports={
            "http-rpc": PortSpec(
                args["zkevm_rpc_http_port"], application_protocol="http"
            ),
            "data-streamer": PortSpec(
                args["zkevm_data_streamer_port"], application_protocol="datastream"
            ),
        },
        env_vars={"CDK_ERIGON_SEQUENCER": "1"},
        node_config_artifact=node_config_artifact,
        chain_spec_artifact=chain_spec_artifact,
        chain_config_artifact=chain_config_artifact,
        chain_allocs_artifact=chain_allocs_artifact,
    )


def start_rpc(
    plan,
    args,
    node_config_artifact,
    chain_spec_artifact,
    chain_config_artifact,
    chain_allocs_artifact,
):
    _start_node(
        plan=plan,
        args=args,
        name="cdk-erigon-rpc" + args["deployment_suffix"],
        ports={
            "http-rpc": PortSpec(
                args["zkevm_rpc_http_port"], application_protocol="http"
            ),
        },
        env_vars={},
        node_config_artifact=node_config_artifact,
        chain_spec_artifact=chain_spec_artifact,
        chain_config_artifact=chain_config_artifact,
        chain_allocs_artifact=chain_allocs_artifact,
    )


def _start_node(
    plan,
    args,
    name,
    ports,
    env_vars,
    node_config_artifact,
    chain_spec_artifact,
    chain_config_artifact,
    chain_allocs_artifact,
):
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
            # Sleep for 10 seconds in order to wait for datastream server getting ready.
            # TODO: Find a better way instead of waiting.
            entrypoint=["sh", "-c"],
            cmd=["sleep 10 && cdk-erigon --config /etc/cdk-erigon/config.yaml"],
            # cmd=["--config=/etc/cdk-erigon/config.yaml"],
        ),
    )
