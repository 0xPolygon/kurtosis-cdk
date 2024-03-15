POSTGRES_IMAGE = "postgres:16.2"


def run(plan, args):
    plan.print("Hello World!")

    cpu_arch = determine_cpu_architecture(plan)
    plan.print("Running on {} CPU architecture".format(cpu_arch))

    start_databases(plan, args)
    start_permissionless_prover(plan, args, cpu_arch)

    genesis_file = read_file(src="./files/genesis.json")
    genesis_artifact = plan.render_templates(
        name="genesis", config={"genesis.json": struct(template=genesis_file, data={})}
    )

    permissionless_node_config_template = read_file(
        src="./templates/permissionless-node-config.toml"
    )
    permissionless_node_config_artifact = plan.render_templates(
        name="permissionless-node-config",
        config={
            "permissionless-node-config.toml": struct(
                template=permissionless_node_config_template, data=args
            )
        },
    )
    start_synchronizer(
        plan, args, permissionless_node_config_artifact, genesis_artifact
    )
    start_rpc(plan, args, permissionless_node_config_artifact, genesis_artifact)


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
        name=args["zkevm_db_event_hostname"] + "-" + args["deployment_idx"],
        port=args["zkevm_db_postgres_port"],
        db="event_db",
        user=args["zkevm_db_event_user"],
        password=args["zkevm_db_event_password"],
        init_script_artifact_name=event_db_init_script,
    )

    # Start pool database
    start_postgres_db(
        plan,
        name=args["zkevm_db_pool_hostname"] + "-" + args["deployment_idx"],
        port=args["zkevm_db_postgres_port"],
        db="pool_db",
        user=args["zkevm_db_pool_user"],
        password=args["zkevm_db_pool_password"],
    )

    # Start prover database
    prover_db_init_script = plan.upload_files(
        src="./templates/prover-db-init.sql", name="prover-db-init.sql"
    )
    start_postgres_db(
        plan,
        name=args["zkevm_db_prover_hostname"] + "-" + args["deployment_idx"],
        port=args["zkevm_db_postgres_port"],
        db="prover_db",
        user=args["zkevm_db_prover_user"],
        password=args["zkevm_db_prover_password"],
        init_script_artifact_name=prover_db_init_script,
    )

    # Start state database
    start_postgres_db(
        plan,
        name=args["zkevm_db_state_hostname"] + "-" + args["deployment_idx"],
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


def start_permissionless_prover(plan, args, cpu_arch):
    permissionless_prover_config_template = read_file(
        src="./templates/permissionless-prover-config.json"
    )
    permissionless_prover_config_artifact = plan.render_templates(
        name="permissionless-prover-config",
        config={
            "permissionless-prover-config.json": struct(
                template=permissionless_prover_config_template, data=args
            )
        },
    )
    plan.add_service(
        name="zkevm-permissionless-prover-" + args["deployment_idx"],
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
                "/etc/zkevm": permissionless_prover_config_artifact,
            },
            entrypoint=["/bin/bash", "-c"],
            cmd=[
                '[[ "{0}" == "aarch64" || "{0}" == "arm64" ]] && export EXPERIMENTAL_DOCKER_DESKTOP_FORCE_QEMU=1; \
                /usr/local/bin/zkProver -c /etc/zkevm/permissionless-prover-config.json'.format(
                    cpu_arch
                ),
            ],
        ),
    )


def start_synchronizer(plan, args, config_artifact, genesis_artifact):
    plan.add_service(
        name="zkevm-permissionless-node-synchronizer-" + args["deployment_idx"],
        config=ServiceConfig(
            image=args["zkevm_node_image"],
            ports={
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
                "--cfg=/etc/zkevm/permissionless-node-config.toml",
                "--network=custom",
                "--custom-network-file=/etc/zkevm/genesis.json",
                "--components=synchronizer",
                "--http.api=eth,net,debug,zkevm,txpool,web3",
            ],
        ),
    )


def start_rpc(plan, args, config_artifact, genesis_artifact):
    plan.add_service(
        name="zkevm-permissionless-node-rpc-" + args["deployment_idx"],
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
                "--cfg=/etc/zkevm/permissionless-node-config.toml",
                "--network=custom",
                "--custom-network-file=/etc/zkevm/genesis.json",
                "--components=rpc",
                "--http.api=eth,net,debug,zkevm,txpool,web3",
            ],
        ),
    )
