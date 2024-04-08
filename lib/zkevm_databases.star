POSTGRES_IMAGE = "postgres:16.2"


def _create_postgres_db_service_config(
    port, db, user, password, init_script_artifact_name=""
):
    files = {}
    if init_script_artifact_name != "":
        files["/docker-entrypoint-initdb.d/"] = init_script_artifact_name
    return ServiceConfig(
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
    )


def create_node_db_service_configs(args, event_db_init_script, prover_db_init_script):
    pool_db_name = args["zkevm_db_pool_hostname"] + args["deployment_suffix"]
    pool_db_service_config = _create_postgres_db_service_config(
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_pool_name"],
        user=args["zkevm_db_pool_user"],
        password=args["zkevm_db_pool_password"],
    )

    state_db_name = args["zkevm_db_state_hostname"] + args["deployment_suffix"]
    state_db_service_config = _create_postgres_db_service_config(
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_state_name"],
        user=args["zkevm_db_state_user"],
        password=args["zkevm_db_state_password"],
    )

    event_db_name = args["zkevm_db_event_hostname"] + args["deployment_suffix"]
    event_db_service_config = _create_postgres_db_service_config(
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_event_name"],
        user=args["zkevm_db_event_user"],
        password=args["zkevm_db_event_password"],
        init_script_artifact_name=event_db_init_script,
    )

    prover_db_name = args["zkevm_db_prover_hostname"] + args["deployment_suffix"]
    prover_db_service_config = _create_postgres_db_service_config(
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_prover_name"],
        user=args["zkevm_db_prover_user"],
        password=args["zkevm_db_prover_password"],
        init_script_artifact_name=prover_db_init_script,
    )

    return {
        pool_db_name: pool_db_service_config,
        state_db_name: state_db_service_config,
        event_db_name: event_db_service_config,
        prover_db_name: prover_db_service_config,
    }


def create_peripheral_databases_service_configs(args):
    bridge_db_name = args["zkevm_db_bridge_hostname"] + args["deployment_suffix"]
    bridge_db_service_config = _create_postgres_db_service_config(
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_bridge_name"],
        user=args["zkevm_db_bridge_user"],
        password=args["zkevm_db_bridge_password"],
    )

    agglayer_db_name = args["zkevm_db_agglayer_hostname"] + args["deployment_suffix"]
    agglayer_db_service_config = _create_postgres_db_service_config(
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_agglayer_name"],
        user=args["zkevm_db_agglayer_user"],
        password=args["zkevm_db_agglayer_password"],
    )

    dac_db_name = args["zkevm_db_dac_hostname"] + args["deployment_suffix"]
    dac_db_service_config = _create_postgres_db_service_config(
        port=args["zkevm_db_postgres_port"],
        db=args["zkevm_db_dac_name"],
        user=args["zkevm_db_dac_user"],
        password=args["zkevm_db_dac_password"],
    )

    return {
        bridge_db_name: bridge_db_service_config,
        agglayer_db_name: agglayer_db_service_config,
        dac_db_name: dac_db_service_config,
    }
