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
    db_user = args["zkevm_db_blockscout_user"]
    db_password = args["zkevm_db_blockscout_password"]
    db_host = args["zkevm_db_blockscout_hostname"] + args["deployment_suffix"]
    db_port = args["zkevm_db_postgres_port"]
    db_name = args["zkevm_db_blockscout_name"]
    connection_string = \
        "postgresql://"+db_user+":"+db_password+"@"+db_host+":"+str(db_port)+"/"+db_name
    return plan.add_service(
        name="blockscout" + args["deployment_suffix"],
        config = ServiceConfig(
            image = args["blockscout_image"],
            ports = {
                "blockscout": PortSpec(
                    4004, application_protocol="http", wait="5m"
                ),
            },
            env_vars = {
                "PORT": "4004",
                "NETWORK": "POE",
                "SUBNETWORK": "Polygon CDK",
                "CHAIN_ID": str(args["zkevm_rollup_chain_id"]),
                "COIN": "ETH",
                "ETHEREUM_JSONRPC_VARIANT": "geth",
                "ETHEREUM_JSONRPC_HTTP_URL": args["zkevm_rpc_url"],
                "DATABASE_URL": connection_string,
                "ECTO_USE_SSL": "false",
                "MIX_ENV": "prod",
                "LOGO": "/images/blockscout_logo.svg",
                "LOGO_FOOTER": "/images/blockscout_logo.svg",
                "SUPPORTED_CHAINS": "[]",
                "SHOW_OUTDATED_NETWORK_MODAL": "false",
                "DISABLE_INDEXER": "false",
                "INDEXER_ZKEVM_BATCHES_ENABLED": "true"
            },
            cmd=[
                "/bin/sh",
                "-c",
                "mix do ecto.create, ecto.migrate; mix phx.server"
            ],
        ),
    )


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
