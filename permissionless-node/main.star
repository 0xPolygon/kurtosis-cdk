POSTGRES_IMAGE = "postgres:16.2"
POSTGRES_PORT_ID = "postgres"


def run(plan, args):
    plan.print("Hello World!")

    start_databases(plan, args)


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
                POSTGRES_PORT_ID: PortSpec(port, application_protocol="postgresql"),
            },
            env_vars={
                "POSTGRES_DB": db,
                "POSTGRES_USER": user,
                "POSTGRES_PASSWORD": password,
            },
            files=files,
        ),
    )
