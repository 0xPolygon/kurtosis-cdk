zkevm_databases_package = import_module("./lib/zkevm_databases.star")


def run(plan, args):
    # Start node and peripheral databases.
    event_db_init_script = plan.upload_files(
        name="event-db-init.sql" + args["deployment_suffix"],
        src="./templates/databases/event-db-init.sql",
    )
    prover_db_init_script = plan.upload_files(
        name="prover-db-init.sql" + args["deployment_suffix"],
        src="./templates/databases/prover-db-init.sql",
    )
    node_db_configs = zkevm_databases_package.create_node_db_service_configs(
        args, event_db_init_script, prover_db_init_script
    )
    peripheral_db_configs = (
        zkevm_databases_package.create_peripheral_databases_service_configs(args)
    )
    plan.add_services(
        configs=node_db_configs | peripheral_db_configs,
        description="Starting node and peripheral databases",
    )
