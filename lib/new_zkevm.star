def run_sequence_sender_and_aggregator(
    plan,
    args,
    db_configs,
    sequence_sender_config_artifact,
    aggregator_config_artifact,
    genesis_artifact,
    keystore_artifacts,
):
    sequence_sender_service_config = _create_sequence_sender_service_config(
        plan,
        args,
        sequence_sender_config_artifact,
        genesis_artifact,
        keystore_artifacts.sequencer,
    )

    aggregator_service_config = _create_aggregator_service_config(
        plan,
        args,
        aggregator_config_artifact,
        genesis_artifact,
        keystore_artifacts.aggregator,
    )
    plan.add_services(
        configs=sequence_sender_service_config | aggregator_service_config,
        description="Starting new zkevm components: zkevm-sequence-sender and zkevm-aggregator",
    )


def _create_sequence_sender_service_config(
    plan, args, config_artifact, genesis_artifact, sequencer_keystore_artifact
):
    sequence_sender_name = "zkevm-sequence-sender" + args["deployment_suffix"]
    sequence_sender_service_config = ServiceConfig(
        image=args["zkevm_sequence_sender_image"],
        files={
            "/etc/zkevm": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    sequencer_keystore_artifact,
                ]
            )
        },
        cmd=[
            "/bin/sh",
            "-c",
            "/app/zkevm-seqsender run --network custom --custom-network-file /etc/zkevm/genesis.json --cfg /etc/zkevm/zkevm-sequence-sender-config.toml",
        ],
    )
    return {sequence_sender_name: sequence_sender_service_config}


def _create_aggregator_service_config(
    plan, args, config_artifact, genesis_artifact, aggregator_keystore_artifact
):
    aggregator_name = "zkevm-aggregator" + args["deployment_suffix"]
    aggregator_service_config = ServiceConfig(
        image=args["zkevm_aggregator_image"],
        ports={
            "aggregator": PortSpec(
                args["zkevm_aggregator_port"], application_protocol="grpc"
            ),
        },
        files={
            "/etc/zkevm": Directory(
                artifact_names=[
                    config_artifact,
                    genesis_artifact,
                    aggregator_keystore_artifact,
                ]
            )
        },
        cmd=[
            "/bin/sh",
            "-c",
            "/app/zkevm-aggregator run --network custom --custom-network-file /etc/zkevm/genesis.json --cfg /etc/zkevm/zkevm-aggregator-config.toml",
        ],
    )
    return {aggregator_name: aggregator_service_config}
