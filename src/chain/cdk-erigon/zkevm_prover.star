cdk_node = import_module("./cdk_node.star")
databases = import_module("../shared/databases.star")


ZKEVM_PROVER_TYPE = struct(
    prover="prover",
    stateless_executor="stateless-executor",
)


# Port identifiers and numbers.
HASH_DB_PORT_ID = "hash-db"
HASH_DB_PORT_NUMBER = 50061

EXECUTOR_PORT_ID = "executor"
EXECUTOR_PORT_NUMBER = 50071


def run_prover(plan, args):
    return _run(plan, args, type=ZKEVM_PROVER_TYPE.prover)


def run_stateless_executor(plan, args):
    return _run(plan, args, type=ZKEVM_PROVER_TYPE.stateless_executor)


def _run(plan, args, type=ZKEVM_PROVER_TYPE.prover):
    if type not in [
        ZKEVM_PROVER_TYPE.prover,
        ZKEVM_PROVER_TYPE.stateless_executor,
    ]:
        fail("Unknown zkevm prover type: {}".format(type))

    stateless_executor = False
    if args.get("erigon_strict_mode"):
        stateless_executor = True

    db_configs = databases.get_db_configs(
        args.get("deployment_suffix"), args.get("sequencer_type")
    )
    config_artifact = plan.render_templates(
        name="zkevm-{}-config-artifact".format(type),
        config={
            "config.json": struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/zkevm-prover/config.json"
                ),
                data=args
                | db_configs
                | {
                    "hash_db_port_number": HASH_DB_PORT_NUMBER,
                    "executor_port_number": EXECUTOR_PORT_NUMBER,
                    "stateless_executor": stateless_executor,
                    "aggregator_port_number": cdk_node.AGGREGATOR_PORT_NUMBER,
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
        name="zkevm-{}{}".format(type, args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("zkevm_prover_image"),
            ports={
                HASH_DB_PORT_ID: PortSpec(
                    HASH_DB_PORT_NUMBER, application_protocol="grpc"
                ),
                EXECUTOR_PORT_ID: PortSpec(
                    EXECUTOR_PORT_NUMBER, application_protocol="grpc"
                ),
            },
            files={
                "/etc/zkevm-{}".format(type): config_artifact,
            },
            entrypoint=["/bin/bash", "-c"],
            cmd=[
                '[[ "{0}" == "aarch64" || "{0}" == "arm64" ]] && export EXPERIMENTAL_DOCKER_DESKTOP_FORCE_QEMU=1; \
                /usr/local/bin/zkProver -c /etc/zkevm-{1}/config.json'.format(
                    cpu_arch, type
                ),
            ],
        ),
    )
