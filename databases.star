# We support both local and remote Postgres databases within our Kurtosis-CDK package
# When 'USE_REMOTE_POSTGRES' is False, service automatically creates all CDK databases locally
# When 'USE_REMOTE_POSTGRES' is True, service is created just as a helper for param injection across pods
# When 'USE_REMOTE_POSTGRES' is True, all state is stored on your preconfigured remote Postgres instances
USE_REMOTE_POSTGRES = False

# When 'USE_REMOTE_POSTGRES' is True, replace 'POSTGRES_HOSTNAME' with your master database IP/hostname
POSTGRES_HOSTNAME = "127.0.0.1"

# Mostly static params unless user has specialized postgres configuration
POSTGRES_IMAGE = "postgres:16.2"
POSTGRES_SERVICE_NAME = "postgres"
POSTGRES_PORT = 5432

# Below 'POSTGRES_MASTER_' params only apply when 'USE_REMOTE_POSTGRES' is False
POSTGRES_MASTER_DB = "master"
POSTGRES_MASTER_USER = "master_user"
POSTGRES_MASTER_PASSWORD = "master_password"

# When 'USE_REMOTE_POSTGRES' is True, update following credentials to match your remote postgres DBs
# It is recommended users keep existing DB names and usernames for stability
# This way, users can also leverage our 'reset_postgres.sh' script,
# Which automatically wipes all CDK databases and reapplies proper db permissions
# TO DO: add env var support for credentials

# Databases that make up the central environment of an L2 chain, including sequencer, aggregator,
# prover, bridge service, and DAC.
CENTRAL_ENV_DBS = {
    "aggregator_db": {
        "name": "aggregator_db",
        "user": "aggregator_user",
        "password": "redacted",
    },
    "aggregator_syncer_db": {
        "name": "aggregator_syncer_db",
        "user": "aggregator_syncer_db_user",
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

# The prover database is a component of both central environment and permissionless zkEVM node environment.
# Therefore, it is defined separately.
PROVER_DB = {
    "prover_db": {
        "name": "prover_db",
        "user": "prover_user",
        "password": "redacted",
        "init": read_file(src="./templates/databases/prover-db-init.sql"),
    }
}

# Databases required for a zkevm node to function as either a sequencer or a permissionless node.
ZKEVM_NODE_DBS = {
    "event_db": {
        "name": "event_db",
        "user": "event_user",
        "password": "redacted",
        "init": read_file(src="./templates/databases/event-db-init.sql"),
    },
    "pool_db": {
        "name": "pool_db",
        "user": "pool_user",
        "password": "redacted",
    },
    "state_db": {
        "name": "state_db",
        "user": "state_user",
        "password": "redacted",
    },
}

# Databases required for a cdk erigon node to function as either a sequencer or a permissionless node.
CDK_ERIGON_DBS = {
    "pool_manager_db": {
        "name": "pool_manager_db",
        "user": "pool_manager_user",
        "password": "redacted",
    }
}

DATABASES = CENTRAL_ENV_DBS | PROVER_DB | ZKEVM_NODE_DBS | CDK_ERIGON_DBS


def run(plan, suffix, sequencer_type):
    db_configs = get_db_configs(suffix, sequencer_type)
    create_postgres_service(plan, db_configs, suffix)


def get_db_configs(suffix, sequencer_type):
    dbs = None
    if sequencer_type == "erigon":
        dbs = CENTRAL_ENV_DBS | PROVER_DB | CDK_ERIGON_DBS
    elif sequencer_type == "zkevm":
        dbs = CENTRAL_ENV_DBS | PROVER_DB | ZKEVM_NODE_DBS
    else:
        fail("Unsupported sequencer type: %s" % sequencer_type)

    configs = {
        k: v
        | {
            "hostname": POSTGRES_HOSTNAME
            if USE_REMOTE_POSTGRES
            else _service_name(suffix),
            "port": POSTGRES_PORT,
        }
        for k, v in dbs.items()
    }
    return configs


def _service_name(suffix):
    return POSTGRES_SERVICE_NAME + suffix


def run_pless_zkevm(plan, suffix):
    db_configs = get_pless_zkevm_db_configs(suffix)
    create_postgres_service(plan, db_configs, _pless_suffix(suffix))


def get_pless_zkevm_db_configs(suffix):
    dbs = ZKEVM_NODE_DBS | PROVER_DB
    configs = {
        k: v
        | {
            "hostname": POSTGRES_HOSTNAME
            if USE_REMOTE_POSTGRES
            else _service_name(_pless_suffix(suffix)),
            "port": POSTGRES_PORT,
        }
        for k, v in dbs.items()
    }
    return configs


def _pless_suffix(suffix):
    return "-pless" + suffix


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
