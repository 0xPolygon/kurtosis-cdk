ports_package = import_module("../src/package_io/ports.star")

PROVER_TYPE = struct(
    prover="prover",
    executor="executor",
    stateless_executor="stateless-executor",
)


def start_prover(plan, args, config_artifact, start_port_name):
    return _start_service(
        plan, PROVER_TYPE.prover, args, config_artifact, start_port_name
    )


def start_executor(plan, args, config_artifact, start_port_name):
    return _start_service(
        plan, PROVER_TYPE.executor, args, config_artifact, start_port_name
    )


def start_stateless_executor(plan, args, config_artifact, start_port_name):
    return _start_service(
        plan, PROVER_TYPE.stateless_executor, args, config_artifact, start_port_name
    )


def _start_service(plan, type, args, config_artifact, start_port_name):
    cpu_arch_result = plan.run_sh(
        description="Determining CPU system architecture",
        run="uname -m | tr -d '\n'",
    )
    cpu_arch = cpu_arch_result.output

    (ports, public_ports) = get_prover_ports(args, start_port_name)
    return plan.add_service(
        name="zkevm-" + type + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_prover_image"],
            ports=ports,
            public_ports=public_ports,
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


def get_prover_ports(args, start_port_name):
    ports = {
        "hash-db": PortSpec(args["zkevm_hash_db_port"], application_protocol="grpc"),
        "executor": PortSpec(args["zkevm_executor_port"], application_protocol="grpc"),
    }
    public_ports = ports_package.get_public_ports(ports, start_port_name, args)
    return (ports, public_ports)
