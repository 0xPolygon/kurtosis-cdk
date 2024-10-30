ports_package = import_module("../src/package_io/ports.star")

CDK_ERIGON_TYPE = struct(
    sequencer="sequencer",
    rpc="rpc",
)


def start_cdk_erigon_sequencer(plan, args, config_artifact, start_port_name):
    ports = {
        "data-streamer": PortSpec(
            args["zkevm_data_streamer_port"], application_protocol="datastream"
        )
    }
    env_vars = {"CDK_ERIGON_SEQUENCER": "1"}
    _start_service(
        plan,
        CDK_ERIGON_TYPE.sequencer,
        args,
        config_artifact,
        start_port_name,
        ports,
        env_vars,
    )


def start_cdk_erigon_rpc(plan, args, config_artifact, start_port_name):
    _start_service(plan, CDK_ERIGON_TYPE.rpc, args, config_artifact, start_port_name)


def _start_service(
    plan, type, args, config_artifact, start_port_name, additional_ports={}, env_vars={}
):
    # Leaving the name out for now.
    # This might cause some idempotency issues, but we're not currently relying on that for now.‡
    proc_runner_file_artifact = plan.upload_files(
        src="../templates/proc-runner.sh",
    )
    cdk_erigon_chain_artifact_names = [
        config_artifact.chain_spec,
        config_artifact.chain_config,
        config_artifact.chain_allocs,
    ]
    (ports, public_ports) = get_cdk_erigon_ports(
        args, additional_ports, start_port_name
    )
    plan.add_service(
        name="cdk-erigon-" + type + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["cdk_erigon_node_image"],
            ports=ports,
            public_ports=public_ports,
            files={
                "/etc/cdk-erigon": Directory(
                    artifact_names=[config_artifact.config]
                    + cdk_erigon_chain_artifact_names,
                ),
                "/home/erigon/dynamic-configs/": Directory(
                    artifact_names=cdk_erigon_chain_artifact_names,
                ),
                "/usr/local/share/proc-runner": proc_runner_file_artifact,
            },
            entrypoint=["/usr/local/share/proc-runner/proc-runner.sh"],
            cmd=["cdk-erigon --config /etc/cdk-erigon/config.yaml"],
            env_vars=env_vars,
        ),
    )


def get_cdk_erigon_ports(args, additional_ports, start_port_name):
    ports = {
        "pprof": PortSpec(
            args["zkevm_pprof_port"], application_protocol="http", wait=None
        ),
        "prometheus": PortSpec(
            args["prometheus_port"], application_protocol="http", wait=None
        ),
        "rpc": PortSpec(args["zkevm_rpc_http_port"], application_protocol="http"),
        "ws-rpc": PortSpec(args["zkevm_rpc_ws_port"], application_protocol="ws"),
    } | additional_ports
    public_ports = ports_package.get_public_ports(ports, start_port_name, args)
    return (ports, public_ports)
