prometheus_package = import_module(
    "github.com/kurtosis-tech/prometheus-package/main.star"
)
grafana_package = import_module("github.com/kurtosis-tech/grafana-package/main.star")

service_package = import_module("./lib/service.star")
bridge_package = import_module("./cdk_bridge_infra.star")


def start_panoptichain(plan, args):
    # Create the panoptichain config.
    panoptichain_config_template = read_file(
        src="./templates/observability/panoptichain-config.yml"
    )
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    panoptichain_config_artifact = plan.render_templates(
        name="panoptichain-config",
        config={
            "config.yml": struct(
                template=panoptichain_config_template,
                data={
                    "l1_rpc_url": args["l1_rpc_url"],
                    "zkevm_rpc_url": args["zkevm_rpc_url"],
                    "l1_chain_id": args["l1_chain_id"],
                    "zkevm_rollup_chain_id": args["zkevm_rollup_chain_id"],
                }
                | contract_setup_addresses,
            )
        },
    )

    # Start panoptichain.
    return plan.add_service(
        name="panoptichain" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["panoptichain_image"],
            ports={
                "prometheus": PortSpec(9090, application_protocol="http"),
            },
            files={"/etc/panoptichain": panoptichain_config_artifact},
        ),
    )


def start_blockscout(plan, args):
    # https://github.com/blockscout/frontend/blob/v1.29.2/docs/ENVS.md
    # https://docs.blockscout.com/for-developers/information-and-settings/env-variables
    # https://github.com/blockscout/blockscout-rs/tree/main/stats#env

    bs_db_user = args["zkevm_db_blockscout_user"]
    bs_db_password = args["zkevm_db_blockscout_password"]
    bs_db_host = args["zkevm_db_blockscout_hostname"] + args["deployment_suffix"]
    bs_db_port = args["zkevm_db_postgres_port"]
    bs_db_name = args["zkevm_db_blockscout_name"]
    bs_connection_string = (
        "postgresql://"
        + bs_db_user
        + ":"
        + bs_db_password
        + "@"
        + bs_db_host
        + ":"
        + str(bs_db_port)
        + "/"
        + bs_db_name
    )

    bs_backed_service_name = "blockscout-be" + args["deployment_suffix"]
    bs_backend_service = plan.add_service(
        name=bs_backed_service_name,
        config=ServiceConfig(
            image=args["blockscout_be_image"],
            ports={
                "blockscout": PortSpec(4004, application_protocol="http", wait="1m"),
            },
            env_vars={
                "PORT": "4004",
                "NETWORK": "POE",
                "SUBNETWORK": "Polygon CDK",
                "CHAIN_ID": str(args["zkevm_rollup_chain_id"]),
                "COIN": "ETH",
                "ETHEREUM_JSONRPC_VARIANT": "geth",
                "ETHEREUM_JSONRPC_HTTP_URL": args["zkevm_rpc_url"],
                "DATABASE_URL": bs_connection_string,
                "ECTO_USE_SSL": "false",
                "MIX_ENV": "prod",
                "LOGO": "/images/blockscout_logo.svg",
                "LOGO_FOOTER": "/images/blockscout_logo.svg",
                "SUPPORTED_CHAINS": "[]",
                "SHOW_OUTDATED_NETWORK_MODAL": "false",
                "DISABLE_INDEXER": "false",
                "INDEXER_ZKEVM_BATCHES_ENABLED": "true",
                "API_V2_ENABLED": "true",
                "BLOCKSCOUT_PROTOCOL": "http",
            },
            cmd=[
                "/bin/sh",
                "-c",
                'bin/blockscout eval "Elixir.Explorer.ReleaseTasks.create_and_migrate()" && bin/blockscout start',
            ],
        ),
    )
    plan.exec(
        description="""
        Allow 30s for blockscout to start indexing,
        otherwise bs/Stats crashes because it expects to find content on DB
        """,
        service_name=bs_backed_service_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "sleep 30"],
        ),
    )

    st_db_user = args["zkevm_db_blockscout_stats_user"]
    st_db_password = args["zkevm_db_blockscout_stats_password"]
    st_db_host = args["zkevm_db_blockscout_stats_hostname"] + args["deployment_suffix"]
    st_db_port = args["zkevm_db_postgres_port"]
    st_db_name = args["zkevm_db_blockscout_stats_name"]
    st_connection_string = (
        "postgresql://"
        + st_db_user
        + ":"
        + st_db_password
        + "@"
        + st_db_host
        + ":"
        + str(st_db_port)
        + "/"
        + st_db_name
    )

    bs_stats_service = plan.add_service(
        name="blockscout-stats" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["blockscout_stats_image"],
            ports={
                "blockscout": PortSpec(
                    # Did not find a way to set the port with an env var so far
                    8050,
                    application_protocol="http",
                    wait="30s",
                ),
            },
            env_vars={
                "STATS__DB_URL": st_connection_string,
                "STATS__BLOCKSCOUT_DB_URL": bs_connection_string,
                "STATS__CREATE_DATABASE": "true",
                "STATS__RUN_MIGRATIONS": "true",
                "STATS__SERVER__HTTP__CORS__ENABLED": "false",
            },
        ),
    )

    bs_visualize_service = plan.add_service(
        name="blockscout-visualize" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["blockscout_visualizer_image"],
            ports={
                "blockscout": PortSpec(8050, application_protocol="http"),
            },
        ),
    )

    bs_frontend_service = plan.add_service(
        name="blockscout-fe" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["blockscout_fe_image"],
            ports={
                "blockscout": PortSpec(8050, application_protocol="http", wait="30s"),
            },
            env_vars={
                "PORT": "8050",
                "NEXT_PUBLIC_NETWORK_NAME": "CDK zkEVM",
                "NEXT_PUBLIC_NETWORK_ID": str(args["zkevm_rollup_chain_id"]),
                "NEXT_PUBLIC_API_HOST": bs_backend_service.ip_address,
                "NEXT_PUBLIC_API_PORT": str(
                    bs_backend_service.ports["blockscout"].number
                ),
                "NEXT_PUBLIC_API_PROTOCOL": "http",
                "NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL": "ws",
                "NEXT_PUBLIC_STATS_API_HOST": "http://{}:{}".format(
                    bs_stats_service.ip_address,
                    bs_stats_service.ports["blockscout"].number,
                ),
                "NEXT_PUBLIC_VISUALIZE_API_HOST": "http://{}:{}".format(
                    bs_visualize_service.ip_address,
                    bs_visualize_service.ports["blockscout"].number,
                ),
                "NEXT_PUBLIC_APP_PROTOCOL": "http",
                "NEXT_PUBLIC_APP_HOST": "127.0.0.1",
                "NEXT_PUBLIC_APP_PORT": "8050",
            },
        ),
    )

    return (bs_backend_service, bs_frontend_service)


def run(plan, args):
    for service in plan.get_services():
        if service.name == "zkevm-node-rpc" + args["deployment_suffix"]:
            args["zkevm_rpc_url"] = "http://{}:{}".format(
                service.ip_address, service.ports["http-rpc"].number
            )

    # Start panoptichain.
    start_panoptichain(plan, args)

    # Start blockscout.
    start_blockscout(plan, args)

    metrics_jobs = []
    for service in plan.get_services():
        if "prometheus" in service.ports:
            metrics_jobs.append(
                {
                    "Name": service.name,
                    "Endpoint": "{0}:{1}".format(
                        service.ip_address,
                        service.ports["prometheus"].number,
                    ),
                }
            )

    # Start prometheus.
    prometheus_url = prometheus_package.run(
        plan,
        metrics_jobs,
        name="prometheus" + args["deployment_suffix"],
    )

    # Start grafana.
    grafana_package.run(
        plan,
        prometheus_url,
        "github.com/0xPolygon/kurtosis-cdk/static-files/dashboards",
        name="grafana" + args["deployment_suffix"],
    )
