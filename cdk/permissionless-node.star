zkevm_node_package = import_module("./lib/zkevm_node.star")
zkevm_dbs_package = import_module("./lib/zkevm_dbs.star")


def run(plan, args):
    cpu_arch = determine_cpu_architecture(plan)
    plan.print("Running on {} CPU architecture".format(cpu_arch))

    event_db_init_script = plan.upload_files(
        src="./templates/event-db-init.sql",
        name="event-db-init.sql" + args["deployment_suffix"],
    )
    executor_db_init_script = plan.upload_files(
        src="./templates/executor-db-init.sql",
        name="executor-db-init.sql" + args["deployment_suffix"],
    )
    zkevm_dbs_package.start_databases(
        plan, args, event_db_init_script, executor_db_init_script
    )
    start_executor(plan, args, cpu_arch)

    genesis_file = read_file(src=args["genesis_file"])
    genesis_artifact = plan.render_templates(
        name="genesis", config={"genesis.json": struct(template=genesis_file, data={})}
    )

    config_template = read_file(src="./templates/pless-node-config.toml")
    config_artifact = plan.render_templates(
        name="node-config",
        config={"node-config.toml": struct(template=config_template, data=args)},
    )
    zkevm_node_package.start_synchronizer(plan, args, config_artifact, genesis_artifact)
    zkevm_node_package.start_rpc(plan, args, config_artifact, genesis_artifact)


def determine_cpu_architecture(plan):
    result = plan.run_sh(run="uname -m | tr -d '\n'")
    return result.output


def start_executor(plan, args, cpu_arch):
    executor_config_template = read_file(src="./templates/executor-config.json")
    executor_config_artifact = plan.render_templates(
        name="executor-config",
        config={
            "executor-config.json": struct(template=executor_config_template, data=args)
        },
    )
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
