def start_blockscout(plan, rpc_url, ws_url, args):
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
                "ETHEREUM_JSONRPC_HTTP_URL": rpc_url,
                "ETHEREUM_JSONRPC_TRACE_URL": rpc_url,
                "ETHEREUM_JSONRPC_WS_URL": ws_url,
                "ETHEREUM_JSONRPC_HTTP_INSECURE": "true",
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
                "blockscout": PortSpec(
                    args["blockscout_public_port"],
                    application_protocol="http",
                    wait="30s",
                ),
            },
            public_ports={
                "blockscout": PortSpec(
                    args["blockscout_public_port"],
                    application_protocol="http",
                    wait="30s",
                ),
            },
            env_vars={
                "PORT": str(args["blockscout_public_port"]),
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
                "NEXT_PUBLIC_APP_PORT": str(args["blockscout_public_port"]),
                "NEXT_PUBLIC_USE_NEXT_JS_PROXY": "true",
                "NEXT_PUBLIC_AD_BANNER_PROVIDER": "none",
                "NEXT_PUBLIC_AD_TEXT_PROVIDER": "none",
            },
        ),
    )

    return (bs_backend_service, bs_frontend_service)


def run(plan, args):
    rpc_url = None
    ws_url = None
    for service in plan.get_services():
        if service.name == "zkevm-node-rpc" + args["deployment_suffix"]:
            rpc_url = "http://{}:{}".format(
                service.ip_address, service.ports["http-rpc"].number
            )
            ws_url = "ws://{}:{}".format(
                service.ip_address, service.ports["ws-rpc"].number
            )
            break

    if not (rpc_url and ws_url):
        fail("Could not find the zkevm-node-rpc service")

    # Start blockscout.
    start_blockscout(plan, rpc_url, ws_url, args)
