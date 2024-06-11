data_availability_package = import_module("./data_availability.star")

NODE_COMPONENTS = struct(
    synchronizer="synchronizer",
    sequencer="sequencer",
    sequence_sender="sequence-sender",
    aggregator="aggregator",
    rpc="rpc",
    eth_tx_manager="eth-tx-manager",
    l2_gas_pricer="l2gaspricer",
)


def _create_node_component_service_config(
    image, ports, config_files, components, http_api={}
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
    return ServiceConfig(
        image=image,
        ports=ports,
        files={
            "/etc/zkevm": config_files,
        },
        entrypoint=["/app/zkevm-node"],
        cmd=cmd,
    )


# The synchronizer is required to run before any other zkevm node component.
# This is why this component does not have a `create_service_config` method.
def start_synchronizer(plan, args, config_artifact, genesis_artifact):
    synchronizer_name = "zkevm-node-synchronizer" + args["deployment_suffix"]
    synchronizer_service_config = _create_node_component_service_config(
        image=data_availability_package.get_node_image(args),
        ports={
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENTS.synchronizer,
    )
    plan.add_service(name=synchronizer_name, config=synchronizer_service_config)


def create_sequencer_service_config(args, config_artifact, genesis_artifact):
    sequencer_name = "zkevm-node-sequencer" + args["deployment_suffix"]
    sequencer_service_config = _create_node_component_service_config(
        image=data_availability_package.get_node_image(args),
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
        components=NODE_COMPONENTS.sequencer + "," + NODE_COMPONENTS.rpc,
        http_api="eth,net,debug,zkevm,txpool,web3",
    )
    return {sequencer_name: sequencer_service_config}


def create_sequence_sender_service_config(
    args, config_artifact, genesis_artifact, sequencer_keystore_artifact
):
    sequence_sender_name = "zkevm-node-sequence-sender" + args["deployment_suffix"]
    sequence_sender_service_config = _create_node_component_service_config(
        image=data_availability_package.get_node_image(args),
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
        components=NODE_COMPONENTS.sequence_sender,
    )
    return {sequence_sender_name: sequence_sender_service_config}


def create_aggregator_service_config(
    args,
    config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
    aggregator_keystore_artifact,
    proofsigner_keystore_artifact,
):
    aggregator_name = "zkevm-node-aggregator" + args["deployment_suffix"]
    aggregator_service_config = _create_node_component_service_config(
        image=data_availability_package.get_node_image(args),
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
                proofsigner_keystore_artifact,
            ]
        ),
        components=NODE_COMPONENTS.aggregator,
    )
    return {aggregator_name: aggregator_service_config}


def create_rpc_service_config(args, config_artifact, genesis_artifact):
    rpc_name = "zkevm-node-rpc" + args["deployment_suffix"]
    rpc_service_config = _create_node_component_service_config(
        image=data_availability_package.get_node_image(args),
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
        components=NODE_COMPONENTS.rpc,
        http_api="eth,net,debug,zkevm,txpool,web3",
    )
    return {rpc_name: rpc_service_config}


def create_eth_tx_manager_service_config(
    args,
    config_artifact,
    genesis_artifact,
    sequencer_keystore_artifact,
    aggregator_keystore_artifact,
):
    eth_tx_manager_name = "zkevm-node-eth-tx-manager" + args["deployment_suffix"]
    eth_tx_manager_service_config = _create_node_component_service_config(
        image=data_availability_package.get_node_image(args),
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
        components=NODE_COMPONENTS.eth_tx_manager,
    )
    return {eth_tx_manager_name: eth_tx_manager_service_config}


def create_l2_gas_pricer_service_config(args, config_artifact, genesis_artifact):
    l2_gas_pricer_name = "zkevm-node-l2-gas-pricer" + args["deployment_suffix"]
    l2_gas_pricer_service_config = _create_node_component_service_config(
        image=data_availability_package.get_node_image(args),
        ports={
            "pprof": PortSpec(args["zkevm_pprof_port"], application_protocol="http"),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
        },
        config_files=Directory(artifact_names=[config_artifact, genesis_artifact]),
        components=NODE_COMPONENTS.l2_gas_pricer,
    )
    return {l2_gas_pricer_name: l2_gas_pricer_service_config}


def create_zkevm_node_components_config(
    args,
    config_artifact,
    genesis_artifact,
    keystore_artifacts,
):
    aggregator_config = create_aggregator_service_config(
        args,
        config_artifact,
        genesis_artifact,
        keystore_artifacts.sequencer,
        keystore_artifacts.aggregator,
        keystore_artifacts.proofsigner,
    )
    rpc_config = create_rpc_service_config(args, config_artifact, genesis_artifact)
    eth_tx_manager_config = create_eth_tx_manager_service_config(
        args,
        config_artifact,
        genesis_artifact,
        keystore_artifacts.sequencer,
        keystore_artifacts.aggregator,
    )
    l2_gas_pricer_config = create_l2_gas_pricer_service_config(
        args, config_artifact, genesis_artifact
    )
    configs = (
        aggregator_config | rpc_config | eth_tx_manager_config | l2_gas_pricer_config
    )

    if args["sequencer_type"] == "zkevm-node":
        sequencer_config = create_sequencer_service_config(
            args, config_artifact, genesis_artifact
        )

        sequence_sender_config = create_sequence_sender_service_config(
            args,
            config_artifact,
            genesis_artifact,
            keystore_artifacts.sequencer,
        )

        return configs | sequencer_config | sequence_sender_config
    else:
        return configs
