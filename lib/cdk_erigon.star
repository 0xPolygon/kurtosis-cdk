zkevm_prover_package = import_module("./zkevm_prover.star")
zkevm_pool_manager_package = import_module("./zkevm_pool_manager.star")


def run_sequencer(
    plan,
    args,
    node_config_artifact,
    chain_artifacts,
):
    start_node(
        plan,
        args,
        node_config_artifact,
        chain_artifacts.spec,
        chain_artifacts.config,
        chain_artifacts.allocs,
        True,
    )


def run_rpc(
    plan,
    args,
    node_config_artifact,
    chain_artifacts,
    zkevm_pool_manager_config_artifact,
):
    start_node(
        plan,
        args,
        node_config_artifact,
        chain_artifacts.spec,
        chain_artifacts.config,
        chain_artifacts.allocs,
        False,
    )
    zkevm_pool_manager_package.run_zkevm_pool_manager(
        plan, args, zkevm_pool_manager_config_artifact
    )


def start_node(
    plan,
    args,
    cdk_erigon_node_config_artifact,
    cdk_erigon_node_chain_spec_artifact,
    cdk_erigon_node_chain_config_artifact,
    cdk_erigon_node_chain_allocs_artifact,
    is_sequencer,
):
    name = args["l2_rpc_name"] + args["deployment_suffix"]
    envs = {"CDK_ERIGON_SEQUENCER": "1" if is_sequencer else "0"}
    ports = {
        "http-rpc": PortSpec(args["zkevm_rpc_http_port"], application_protocol="http"),
        "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
        "prometheus": PortSpec(
            args["zkevm_prometheus_port"], application_protocol="http"
        ),
    }

    if is_sequencer:
        name = args["sequencer_name"] + args["deployment_suffix"]
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
