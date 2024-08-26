def create_zkevm_aggregator_config(
    args,
    aggregator_config_artifact,
    genesis_artifact,
    aggregator_keystore_artifact,
):
    zkevm_aggregator_name = "zkevm-aggregator" + args["deployment_suffix"]
    zkevm_aggregator_service_config = ServiceConfig(
        image=args["zkevm_aggregator_image"],
        ports={
            "aggregator": PortSpec(
                args["zkevm_aggregator_port"], application_protocol="grpc"
            ),
        },
        files={
            "/etc/zkevm": Directory(
                artifact_names=[
                    aggregator_config_artifact,
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
    return {zkevm_aggregator_name: zkevm_aggregator_service_config}
