def create_agglayer_service_config(args, config_artifact, agglayer_keystore_artifact):
    return ServiceConfig(
        image=args["zkevm_agglayer_image"],
        ports={
            "agglayer": PortSpec(
                args["zkevm_agglayer_port"], application_protocol="http"
            ),
            "prometheus": PortSpec(
                args["zkevm_prometheus_port"], application_protocol="http"
            ),
        },
        files={
            "/etc/zkevm": Directory(
                artifact_names=[
                    config_artifact,
                    agglayer_keystore_artifact,
                ]
            ),
        },
        entrypoint=[
            "/usr/local/bin/agglayer",
        ],
        cmd=["run", "--cfg", "/etc/zkevm/agglayer-config.toml"],
    )
