def create_zkevm_pool_manager_service_config(args, config_artifact):
    zkevm_pool_manager_service_name = "zkevm-pool-manager" + args["deployment_suffix"]
    zkevm_pool_manager_service_config = ServiceConfig(
        image=args["zkevm_pool_manager_image"],
        ports={
            "http": PortSpec(
                args["zkevm_pool_manager_port"], application_protocol="http"
            ),
        },
        files={
            "/etc/pool-manager": Directory(artifact_names=[config_artifact]),
        },
        entrypoint=["/bin/sh", "-c"],
        # cmd=["run", "--cfg", "/app/pool-manager-config.toml"],
        cmd=[
            "/app/zkevm-pool-manager run --cfg /etc/pool-manager/pool-manager-config.toml",
        ],
    )
    return {zkevm_pool_manager_service_name: zkevm_pool_manager_service_config}
