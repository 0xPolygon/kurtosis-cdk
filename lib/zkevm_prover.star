def start_executor(plan, args, executor_config_artifact):
    cpu_arch_result = plan.run_sh(run="uname -m | tr -d '\n'")
    cpu_arch = cpu_arch_result.output

    plan.add_service(
        name="zkevm-executor" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_prover_image"],
            ports={
                "hash-db-server": PortSpec(
                    args["zkevm_hash_db_port"], application_protocol="grpc"
                ),
                "executor-server": PortSpec(
                    args["zkevm_executor_port"], application_protocol="grpc"
                ),
            },
            files={
                "/etc/zkevm": executor_config_artifact,
            },
            entrypoint=["/bin/bash", "-c"],
            cmd=[
                '[[ "{0}" == "aarch64" || "{0}" == "arm64" ]] && export EXPERIMENTAL_DOCKER_DESKTOP_FORCE_QEMU=1; \
                /usr/local/bin/zkProver -c /etc/zkevm/executor-config.json'.format(
                    cpu_arch
                ),
            ],
        ),
    )
