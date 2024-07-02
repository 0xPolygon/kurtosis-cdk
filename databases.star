USE_REMOTE_POSTGRES = True

POSTGRES_HOSTNAME = "127.0.0.1"  # replace when USE_REMOTE_POSTGRES set True
POSTGRES_IMAGE = "postgres:16.2"
POSTGRES_SERVICE_NAME = "postgres"
POSTGRES_PORT = 5432
POSTGRES_MASTER_DB = "master"
POSTGRES_MASTER_USER = "master_user"
POSTGRES_MASTER_PASSWORD = "master_password"

CDK_DATABASES = {
    "event_db": {
        "name": "event_db",
        "user": "event_user",
        "password": "redacted",
    },
    "pool_db": {
        "name": "pool_db",
        "user": "pool_user",
        "password": "redacted",
    },
    "prover_db": {
        "name": "prover_db",
        "user": "prover_user",
        "password": "redacted",
    },
    "state_db": {
        "name": "state_db",
        "user": "state_user",
        "password": "redacted",
    },
}

DATABASES = CDK_DATABASES | {
    "agglayer_db": {
        "name": "agglayer_db",
        "user": "agglayer_user",
        "password": "redacted",
    },
    "bridge_db": {
        "name": "bridge_db",
        "user": "bridge_user",
        "password": "redacted",
    },
    "dac_db": {
        "name": "dac_db",
        "user": "dac_user",
        "password": "redacted",
    },
}


def _service_name(suffix):
    return POSTGRES_SERVICE_NAME + suffix


def _pless_suffix(suffix):
    return "-pless" + suffix


def get_db_configs(suffix):
    configs = {
        k: v | {"hostname": POSTGRES_HOSTNAME if USE_REMOTE_POSTGRES else _service_name(suffix), "port": POSTGRES_PORT}
        for k, v in DATABASES.items()
    }
    print("DB Configs:", configs)
    return configs

def get_pless_db_configs(suffix):
    configs = {
        k: v | {"hostname": POSTGRES_HOSTNAME if USE_REMOTE_POSTGRES else _service_name(_pless_suffix(suffix)), "port": POSTGRES_PORT}
        for k, v in CDK_DATABASES.items()
    }
    print("Pless DB Configs:", configs)
    return configs

def create_postgres_service(plan, db_configs, suffix):
    init_script_tpl = read_file(src="./templates/databases/init.sql")
    init_script = plan.render_templates(
        name="init.sql" + suffix,
        config={
            "init.sql": struct(
                template=init_script_tpl,
                data={
                    "dbs": db_configs,
                    "master_db": POSTGRES_MASTER_DB,
                    "master_user": POSTGRES_MASTER_USER,
                },
            )
        },
    )

    postgres_service_cfg = ServiceConfig(
        image=POSTGRES_IMAGE,
        ports={
            "postgres": PortSpec(POSTGRES_PORT, application_protocol="postgresql"),
        },
        env_vars={
            "POSTGRES_DB": POSTGRES_MASTER_DB,
            "POSTGRES_USER": POSTGRES_MASTER_USER,
            "POSTGRES_PASSWORD": POSTGRES_MASTER_PASSWORD,
        },
        files={"/docker-entrypoint-initdb.d/": init_script},
        cmd=["-N 1000"],
    )

    plan.add_service(
        name=_service_name(suffix),
        config=postgres_service_cfg,
        description="Starting Postgres Service",
    )
    print("Postgres service config:", postgres_service_cfg)


def run(plan, suffix):
    db_configs = get_db_configs(suffix)
    create_postgres_service(plan, db_configs, suffix)


def run_pless(plan, suffix):
    db_configs = get_pless_db_configs(suffix)
    create_postgres_service(plan, db_configs, _pless_suffix(suffix))
