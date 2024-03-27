zkevm_databases_package = import_module("./lib/zkevm_databases.star")


def run(plan, args):
    # Start zkevm node databases.
    event_db_init_script = plan.upload_files(
        name="event-db-init.sql" + args["deployment_suffix"],
        src="./templates/databases/event-db-init.sql",
    )
    prover_db_init_script = plan.upload_files(
        name="prover-db-init.sql" + args["deployment_suffix"],
        src="./templates/databases/prover-db-init.sql",
    )
    zkevm_databases_package.start_node_databases(
        plan, args, event_db_init_script, prover_db_init_script
    )

    # Start cdk peripheral databases.
    zkevm_databases_package.start_peripheral_databases(plan, args)
