NODE_COMPONENT = struct(
    synchronizer="synchronizer",
    sequencer="sequencer",
    sequence_sender="sequence-sender",
    aggregator="aggregator",
    rpc="rpc",
    eth_tx_manager="eth-tx-manager",
    l2_gas_pricer="l2gaspricer",
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
    return plan.add_service(
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


def start_synchronizer(plan, args, config_artifact, genesis_artifact):
    return _start_node_component(
        plan,
        name="zkevm-node-synchronizer" + args["deployment_suffix"],
        image=args["zkevm_node_image"],
        ports={
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENT.synchronizer,
    )


def start_sequencer(plan, args, config_artifact, genesis_artifact):
    return _start_node_component(
        plan,
        name="zkevm-node-sequencer" + args["deployment_suffix"],
        image=args["zkevm_node_image"],
        ports={
            "rpc": PortSpec(args["zkevm_rpc_http_port"], application_protocol="http"),
            "data-streamer": PortSpec(
                args["zkevm_data_streamer_port"], application_protocol="datastream"
            ),
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENT.sequencer + "," + NODE_COMPONENT.rpc,
        http_api="eth,net,debug,zkevm,txpool,web3",
    )


def start_sequence_sender(
    plan,
    args,
    config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
):
    return _start_node_component(
        plan,
        name="zkevm-node-sequence-sender" + args["deployment_suffix"],
        image=args["zkevm_node_image"],
        ports={
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
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
    args,
    config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
    aggregator_keystore_artifact,
):
    return _start_node_component(
        plan,
        name="zkevm-node-aggregator" + args["deployment_suffix"],
        image=args["zkevm_node_image"],
        ports={
            "aggregator": PortSpec(
                args["zkevm_aggregator_port"], application_protocol="grpc"
            ),
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
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


def start_rpc(plan, args, config_artifact, genesis_artifact):
    return _start_node_component(
        plan,
        name="zkevm-node-rpc" + args["deployment_suffix"],
        image=args["zkevm_node_image"],
        ports={
            "http-rpc": PortSpec(
                args["zkevm_rpc_http_port"], application_protocol="http"
            ),
            "ws-rpc": PortSpec(args["zkevm_rpc_ws_port"], application_protocol="ws"),
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENT.rpc,
        http_api="eth,net,debug,zkevm,txpool,web3",
    )


def start_eth_tx_manager(
    plan,
    args,
    config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
    aggregator_keystore_artifact,
):
    return _start_node_component(
        plan,
        name="zkevm-node-eth-tx-manager" + args["deployment_suffix"],
        image=args["zkevm_node_image"],
        ports={
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
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


def start_l2_gas_pricer(plan, args, config_artifact, genesis_artifact):
    return _start_node_component(
        plan,
        name="zkevm-node-l2-gas-pricer" + args["deployment_suffix"],
        image=args["zkevm_node_image"],
        ports={
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENT.l2_gas_pricer,
    )
