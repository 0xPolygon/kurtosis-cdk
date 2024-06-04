PROVER_TYPE = struct(
    prover="prover",
    executor="executor",
)


def start_prover(plan, args, config_artifact):
    return _start_service(plan, PROVER_TYPE.prover, args, config_artifact)


def start_executor(plan, args, config_artifact):
    return _start_service(plan, PROVER_TYPE.executor, args, config_artifact)


def _start_service(plan, type, args, config_artifact):
    cpu_arch_result = plan.run_sh(
        description="Determining CPU system architecture",
        run="uname -m | tr -d '\n'",
    )
    cpu_arch = cpu_arch_result.output

    return plan.add_service(
        name="zkevm-" + type + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_prover_image"],
            ports={
                "hash-db": PortSpec(
                    args["zkevm_hash_db_port"], application_protocol="grpc"
                ),
                "executor": PortSpec(
                    args["zkevm_executor_port"], application_protocol="grpc"
                ),
            },
            files={
                "/etc/zkevm": config_artifact,
            },
            entrypoint=["/bin/bash", "-c"],
            cmd=[
                '[[ "{0}" == "aarch64" || "{0}" == "arm64" ]] && export EXPERIMENTAL_DOCKER_DESKTOP_FORCE_QEMU=1; \
                /usr/local/bin/zkProver -c /etc/zkevm/{1}-config.json'.format(
                    cpu_arch, type
                ),
            ],
        ),
    )
