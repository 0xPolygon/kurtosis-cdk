cdk_node = import_module("./cdk_node.star")
constants = import_module("../../package_io/constants.star")
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

    is_running_in_strict_mode = (
        type == ZKEVM_PROVER_TYPE.stateless_executor and args.get("erigon_strict_mode")
    )

    # Determine database url
    db_configs = databases.get_db_configs(
        args.get("deployment_suffix"), args.get("sequencer_type")
    )
    prover_db = db_configs.prover_db
    database_url = "postgresql://{}:{}@{}:{}/{}".format(
        prover_db.user,
        prover_db.password,
        prover_db.hostname,
        prover_db.port,
        prover_db.name,
    )

    config_artifact = plan.render_templates(
        name="zkevm-{}-config{}".format(type, args.get("deployment_suffix")),
        config={
            "config.json": struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/zkevm-prover/config.json"
                ),
                data=args
                | {
                    "is_running_in_strict_mode": is_running_in_strict_mode,
                    # ports
                    "executor_port_number": EXECUTOR_PORT_NUMBER,
                    "hash_db_port_number": HASH_DB_PORT_NUMBER,
                    # aggregator (cdk-node)
                    "aggregator_port_number": cdk_node.AGGREGATOR_PORT_NUMBER,
                    "aggregator_host": "cdk-node{}".format(
                        args.get("deployment_suffix")
                    ),
                    # database
                    "database_url": database_url,
                },
            )
        },
    )

    cpu_arch_result = plan.run_sh(
        description="Determining CPU system architecture",
        run="uname -m | tr -d '\n'",
    )
    cpu_arch = cpu_arch_result.output

    result = plan.add_service(
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
    executor_url = result.ports[EXECUTOR_PORT_ID].url
    return struct(
        executor_url=executor_url,
    )
