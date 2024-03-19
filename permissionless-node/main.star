prometheus_package = import_module("github.com/kurtosis-tech/prometheus-package/main.star") 

POSTGRES_IMAGE = "postgres:16.2"


def run(plan, args):
    cpu_arch = determine_cpu_architecture(plan)
    plan.print("Running on {} CPU architecture".format(cpu_arch))

    start_databases(plan, args)
    start_executor(plan, args, cpu_arch)

    genesis_file = read_file(src=args["genesis_file"])
    genesis_artifact = plan.render_templates(
        name="genesis", config={"genesis.json": struct(template=genesis_file, data={})}
    )

    node_config_template = read_file(src="./templates/node-config.toml")
    node_config_artifact = plan.render_templates(
        name="node-config",
        config={"node-config.toml": struct(template=node_config_template, data=args)},
    )
    synchronizer = start_synchronizer(plan, args, node_config_artifact, genesis_artifact)
    rpc = start_rpc(plan, args, node_config_artifact, genesis_artifact)

    prometheus_services = [
        synchronizer,
        rpc,
    ]

    metrics_jobs = [{
        "Name": service.name,
        "Endpoint": "{0}:{1}".format(
            service.ip_address,
            service.ports["prometheus"].number,
        ),
    } for service in prometheus_services]

    prometheus_url = prometheus_package.run(plan, metrics_jobs)


def determine_cpu_architecture(plan):
    result = plan.run_sh(run="uname -m | tr -d '\n'")
    return result.output


def start_databases(plan, args):
    # Start event database
    event_db_init_script = plan.upload_files(
        src="./templates/event-db-init.sql", name="event-db-init.sql"
    )
    start_postgres_db(
        plan,
        name=args["zkevm_db_event_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db="event_db",
        user=args["zkevm_db_event_user"],
        password=args["zkevm_db_event_password"],
        init_script_artifact_name=event_db_init_script,
    )

    # Start pool database
    start_postgres_db(
        plan,
        name=args["zkevm_db_pool_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db="pool_db",
        user=args["zkevm_db_pool_user"],
        password=args["zkevm_db_pool_password"],
    )

    # Start executor database
    executor_db_init_script = plan.upload_files(
        src="./templates/executor-db-init.sql", name="executor-db-init.sql"
    )
    start_postgres_db(
        plan,
        name=args["zkevm_db_executor_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db="executor_db",
        user=args["zkevm_db_executor_user"],
        password=args["zkevm_db_executor_password"],
        init_script_artifact_name=executor_db_init_script,
    )

    # Start state database
    start_postgres_db(
        plan,
        name=args["zkevm_db_state_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db="state_db",
        user=args["zkevm_db_state_user"],
        password=args["zkevm_db_state_password"],
    )


def start_postgres_db(
    plan, name, port, db, user, password, init_script_artifact_name=""
):
    files = {}
    if init_script_artifact_name != "":
        files["/docker-entrypoint-initdb.d/"] = init_script_artifact_name

    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=POSTGRES_IMAGE,
            ports={
                "postgres": PortSpec(port, application_protocol="postgresql"),
            },
            env_vars={
                "POSTGRES_DB": db,
                "POSTGRES_USER": user,
                "POSTGRES_PASSWORD": password,
            },
            files=files,
        ),
    )


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
            image=args["zkevm_executor_image"],
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


def start_synchronizer(plan, args, config_artifact, genesis_artifact):
    return plan.add_service(
        name="zkevm-node-synchronizer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            ports={
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"],
                    application_protocol="http",
                ),
            },
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[config_artifact, genesis_artifact]
                ),
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg=/etc/zkevm/node-config.toml",
                "--network=custom",
                "--custom-network-file=/etc/zkevm/genesis.json",
                "--components=synchronizer",
                "--http.api=eth,net,debug,zkevm,txpool,web3",
            ],
        ),
    )


def start_rpc(plan, args, config_artifact, genesis_artifact):
    return plan.add_service(
        name="zkevm-node-rpc" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            ports={
                "rpc": PortSpec(
                    args["zkevm_rpc_http_port"], application_protocol="http"
                ),
                "ws": PortSpec(args["zkevm_rpc_ws_port"], application_protocol="ws"),
                "pprof": PortSpec(
                    args["zkevm_pprof_port"], application_protocol="http"
                ),
                "prometheus": PortSpec(
                    args["zkevm_prometheus_port"], application_protocol="http"
                ),
            },
            files={
                "/etc/zkevm": Directory(
                    artifact_names=[config_artifact, genesis_artifact]
                ),
            },
            entrypoint=[
                "/app/zkevm-node",
            ],
            cmd=[
                "run",
                "--cfg=/etc/zkevm/node-config.toml",
                "--network=custom",
                "--custom-network-file=/etc/zkevm/genesis.json",
                "--components=rpc",
                "--http.api=eth,net,debug,zkevm,txpool,web3",
            ],
        ),
    )
