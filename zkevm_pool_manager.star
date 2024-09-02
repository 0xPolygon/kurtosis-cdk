zkevm_pool_manager_package = import_module("./lib/zkevm_pool_manager.star")
databases = import_module("./databases.star")


def run_zkevm_pool_manager(plan, args):
    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    zkevm_pool_manager_config_artifact = create_zkevm_pool_manager_config_artifact(
        plan, args, db_configs
    )
    zkevm_pool_manager_config = (
        zkevm_pool_manager_package.create_zkevm_pool_manager_service_config(
            args, zkevm_pool_manager_config_artifact
        )
    )

    # Start the pool manager service.
    zkevm_pool_manager_services = plan.add_services(
        configs=zkevm_pool_manager_config,
        description="Starting pool manager infra",
    )


def create_zkevm_pool_manager_config_artifact(plan, args, db_configs):
    zkevm_pool_manager_config_template = read_file(
        src="./templates/pool-manager/pool-manager-config.toml"
    )
    return plan.render_templates(
        name="pool-manager-config-artifact",
        config={
            "pool-manager-config.toml": struct(
                template=zkevm_pool_manager_config_template,
                data=args
                | {
                    "deployment_suffix": args["deployment_suffix"],
                    "zkevm_pool_manager_port": args["zkevm_pool_manager_port"],
                    # ports
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                }
                | db_configs,
            )
        },
    )
