prometheus_package = import_module(
    "github.com/kurtosis-tech/prometheus-package/main.star"
)
grafana_package = import_module(
    "github.com/kurtosis-tech/grafana-package/main.star@6772a4e4ae07cf5256b8a10e466587b73119bab5"
)
service_package = import_module("./lib/service.star")
databases_package = import_module("./databases.star")


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


def run(plan, args):
    for service in plan.get_services():
        if service.name == args["l2_rpc_name"] + args["deployment_suffix"]:
            args["zkevm_rpc_url"] = "http://{}:{}".format(
                service.ip_address, service.ports["http-rpc"].number
            )

        if (
            service.name
            == databases_package.POSTGRES_SERVICE_NAME + args["deployment_suffix"]
        ):
            args["postgres_url"] = "{}:{}".format(
                service.ip_address, service.ports["postgres"].number
            )

    # Start panoptichain.
    start_panoptichain(plan, args)

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

    grafana_alerting_data = {}
    if "slack_alerts" in args:
        grafana_alerting_data = {
            "SlackChannel": args["slack_alerts"]["slack_channel"],
            "SlackToken": args["slack_alerts"]["slack_token"],
            "MentionUsers": args["slack_alerts"]["mention_users"],
        }

    databases = []
    for database in databases_package.DATABASES.values():
        databases.append(
            {
                "URL": args["postgres_url"],
                "Name": database["name"],
                "User": database["user"],
                "Password": database["password"],
                "Version": 1500,
            }
        )

    # Start grafana.
    grafana_package.run(
        plan,
        prometheus_url,
        "github.com/0xPolygon/kurtosis-cdk/static-files/dashboards",
        name="grafana" + args["deployment_suffix"],
        grafana_version="11.1.0",
        grafana_alerting_template="github.com/0xPolygon/kurtosis-cdk/static-files/alerting.yml.tmpl",
        grafana_alerting_data=grafana_alerting_data,
        postgres_databases=databases,
    )
