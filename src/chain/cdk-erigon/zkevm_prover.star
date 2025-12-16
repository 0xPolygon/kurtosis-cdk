# Port identifiers and numbers.
HASH_DB_PORT_ID = "hash-db"
HASH_DB_PORT_NUMBER = 50061

EXECUTOR_PORT_ID = "executor"
EXECUTOR_PORT_NUMBER = 50071


def run(plan, args):
    config_artifact = plan.render_templates(
        name="zkevm-prover-config-artifact",
        config={
            "config.json": struct(
                template=read_file(src="../../../templates/cdk-erigon/prover.json"),
                data=args
                | db_configs
                | {
                    "hash_db_port_number": HASH_DB_PORT_NUMBER,
                    "executor_port_number": EXECUTOR_PORT_NUMBER,
                },
            )
        },
    )

    cpu_arch_result = plan.run_sh(
        description="Determining CPU system architecture",
        run="uname -m | tr -d '\n'",
    )
    cpu_arch = cpu_arch_result.output

    return plan.add_service(
        name="zkevm-prover" + args.get("deployment_suffix"),
        config=ServiceConfig(
            image=args.get("zkevm_prover_image"),
            ports={
                HASH_DB_PORT_ID: PortSPec(
                    HASH_DB_PORT_NUMBER, application_protocol="grpc"
                ),
                EXECUTOR_PORT_ID: PortSpec(
                    EXECUTOR_PORT_NUMBER, application_protocol="grpc"
                ),
            },
            files={
                "/etc/zkevm-prover": config_artifact,
            },
            entrypoint=["/bin/bash", "-c"],
            cmd=[
                '[[ "{0}" == "aarch64" || "{0}" == "arm64" ]] && export EXPERIMENTAL_DOCKER_DESKTOP_FORCE_QEMU=1; \
                /usr/local/bin/zkProver -c /etc/zkevm-prover/config.json'.format(
                    cpu_arch
                ),
            ],
        ),
    )
