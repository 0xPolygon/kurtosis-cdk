POSTGRES_IMAGE = "postgres:16.2"


def _start_postgres_db(
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


def start_databases(plan, args, event_db_init_script, executor_db_init_script):
    # Start event database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_event_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db="event_db",
        user=args["zkevm_db_event_user"],
        password=args["zkevm_db_event_password"],
        init_script_artifact_name=event_db_init_script,
    )

    # Start pool database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_pool_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db="pool_db",
        user=args["zkevm_db_pool_user"],
        password=args["zkevm_db_pool_password"],
    )

    # Start executor database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_executor_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db="executor_db",
        user=args["zkevm_db_executor_user"],
        password=args["zkevm_db_executor_password"],
        init_script_artifact_name=executor_db_init_script,
    )

    # Start state database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_state_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db="state_db",
        user=args["zkevm_db_state_user"],
        password=args["zkevm_db_state_password"],
    )
