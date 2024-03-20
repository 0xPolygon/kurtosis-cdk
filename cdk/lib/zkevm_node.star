POSTGRES_IMAGE = "postgres:16.2"

NODE_COMPONENT = struct(
    synchronizer="synchronizer",
    sequencer="sequencer",
    sequence_sender="sequence-sender",
    aggregator="aggregator",
    rpc="rpc",
    eth_tx_manager="eth-tx-manager",
    l2_gas_pricer="l2-gas-pricer",
)


def _start_node_component(
    plan, name, image, ports, config_files, components, http_api={}
):
    cmd = [
        "run",
        "--cfg=/etc/zkevm/node-config.toml",
        "--network=custom",
        "--custom-network-file=/etc/zkevm/genesis.json",
        "--components=" + components,
    ]
    if http_api:
        cmd.append("--http.api=" + http_api)
    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=image,
            ports=ports,
            files={
                "/etc/zkevm": config_files,
            },
            entrypoint=["/app/zkevm-node"],
            cmd=cmd,
        ),
    )


def start_synchronizer(
    plan, name, image, pprof_port, prometheus_port, config_artifact, genesis_artifact
):
    _start_node_component(
        plan=plan,
        name=name,
        image=image,
        ports={
            "pprof": PortSpec(pprof_port, application_protocol="http"),
            "prometheus": PortSpec(prometheus_port, application_protocol="http"),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENT.synchronizer,
    )


def start_sequencer(
    plan,
    name,
    image,
    rpc_http_port,
    data_streamer_port,
    pprof_port,
    prometheus_port,
    config_artifact,
    genesis_artifact,
    http_api,
):
    _start_node_component(
        plan=plan,
        name=name,
        image=image,
        ports={
            "rpc": PortSpec(rpc_http_port, application_protocol="http"),
            "data-streamer": PortSpec(
                data_streamer_port, application_protocol="datastream"
            ),
            "pprof": PortSpec(pprof_port, application_protocol="http"),
            "prometheus": PortSpec(prometheus_port, application_protocol="http"),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENT.sequencer + "," + NODE_COMPONENT.rpc,
        http_api=http_api,
    )


def start_sequence_sender(
    plan,
    name,
    image,
    pprof_port,
    prometheus_port,
    config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
):
    _start_node_component(
        plan=plan,
        name=name,
        image=image,
        ports={
            "pprof": PortSpec(pprof_port, application_protocol="http"),
            "prometheus": PortSpec(prometheus_port, application_protocol="http"),
        },
        config_files=Directory(
            artifact_names=[
                config_artifact,
                genesis_artifact,
                sequencer_keystore_artifact,
            ]
        ),
        components=NODE_COMPONENT.sequence_sender,
    )


def start_aggregator(
    plan,
    name,
    image,
    aggregator_port,
    pprof_port,
    prometheus_port,
    config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
    aggregator_keystore_artifact,
):
    _start_node_component(
        plan=plan,
        name=name,
        image=image,
        ports={
            "aggregator": PortSpec(aggregator_port, application_protocol="grpc"),
            "pprof": PortSpec(pprof_port, application_protocol="http"),
            "prometheus": PortSpec(prometheus_port, application_protocol="http"),
        },
        config_files=Directory(
            artifact_names=[
                config_artifact,
                genesis_artifact,
                sequencer_keystore_artifact,
                aggregator_keystore_artifact,
            ]
        ),
        components=NODE_COMPONENT.aggregator,
    )


def start_rpc(
    plan,
    name,
    image,
    rpc_http_port,
    rpc_ws_port,
    pprof_port,
    prometheus_port,
    config_artifact,
    genesis_artifact,
    http_api,
):
    _start_node_component(
        plan=plan,
        name=name,
        image=image,
        ports={
            "http-rpc": PortSpec(rpc_http_port, application_protocol="http"),
            "ws-rpc": PortSpec(rpc_ws_port, application_protocol="ws"),
            "pprof": PortSpec(pprof_port, application_protocol="http"),
            "prometheus": PortSpec(prometheus_port, application_protocol="http"),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENT.rpc,
    )


def start_eth_tx_manager(
    plan,
    name,
    image,
    pprof_port,
    prometheus_port,
    config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
    aggregator_keystore_artifact,
):
    _start_node_component(
        plan=plan,
        name=name,
        image=image,
        ports={
            "pprof": PortSpec(pprof_port, application_protocol="http"),
            "prometheus": PortSpec(prometheus_port, application_protocol="http"),
        },
        config_files=Directory(
            artifact_names=[
                config_artifact,
                genesis_artifact,
                sequencer_keystore_artifact,
                aggregator_keystore_artifact,
            ]
        ),
        components=NODE_COMPONENT.eth_tx_manager,
    )


def start_l2_gas_pricer(
    plan, name, image, pprof_port, prometheus_port, config_artifact, genesis_artifact
):
    _start_node_component(
        plan=plan,
        name=name,
        image=image,
        ports={
            "pprof": PortSpec(pprof_port, application_protocol="http"),
            "prometheus": PortSpec(prometheus_port, application_protocol="http"),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENT.l2_gas_pricer,
    )
