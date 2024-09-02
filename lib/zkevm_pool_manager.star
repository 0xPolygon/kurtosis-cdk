def run_zkevm_pool_manager(plan, args, config_artifact):
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
    plan.add_service(
        name=zkevm_pool_manager_service_name,
        config=zkevm_pool_manager_service_config,
        description="Starting zkevm pool manager",
    )
