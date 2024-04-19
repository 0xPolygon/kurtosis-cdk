def create_dac_service_config(args, config_artifact, dac_keystore_artifact):
    dac_name = "zkevm-dac" + args["deployment_suffix"]
    dac_service_config = ServiceConfig(
        image=args["zkevm_da_image"],
        ports={
            "dac": PortSpec(args["zkevm_dac_port"], application_protocol="http"),
        },
        files={
            "/etc/zkevm": Directory(
                artifact_names=[config_artifact, dac_keystore_artifact]
            ),
        },
        entrypoint=[
            "/app/cdk-data-availability",
        ],
        cmd=["run", "--cfg", "/etc/zkevm/dac-config.toml"],
    )
    return {dac_name: dac_service_config}
