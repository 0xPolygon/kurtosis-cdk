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


def start_node_databases(plan, args, event_db_init_script, prover_db_init_script):
    # Start event database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_event_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_event_name"],
        user=args["zkevm_db_event_user"],
        password=args["zkevm_db_event_password"],
        init_script_artifact_name=event_db_init_script,
    )

    # Start pool database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_pool_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_pool_name"],
        user=args["zkevm_db_pool_user"],
        password=args["zkevm_db_pool_password"],
    )

    # Start prover database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_prover_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_prover_name"],
        user=args["zkevm_db_prover_user"],
        password=args["zkevm_db_prover_password"],
        init_script_artifact_name=prover_db_init_script,
    )

    # Start state database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_state_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_state_name"],
        user=args["zkevm_db_state_user"],
        password=args["zkevm_db_state_password"],
    )


def start_peripheral_databases(plan, args):
    # Start bridge database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_bridge_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_bridge_name"],
        user=args["zkevm_db_bridge_user"],
        password=args["zkevm_db_bridge_password"],
    )

    # Start agglayer database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_agglayer_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_agglayer_name"],
        user=args["zkevm_db_agglayer_user"],
        password=args["zkevm_db_agglayer_password"],
    )

    # Start dac database.
    _start_postgres_db(
        plan,
        name=args["zkevm_db_dac_hostname"] + args["deployment_suffix"],
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_dac_name"],
        user=args["zkevm_db_dac_user"],
        password=args["zkevm_db_dac_password"],
    )
