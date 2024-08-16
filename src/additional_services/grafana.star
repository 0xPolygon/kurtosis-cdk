databases_package = import_module("../../databases.star")
grafana_package = import_module(
    "github.com/kurtosis-tech/grafana-package/main.star@6772a4e4ae07cf5256b8a10e466587b73119bab5"
)

GRAFANA_VERSION = "11.1.4"
GRAFANA_DASHBOARDS = "github.com/0xPolygon/kurtosis-cdk/static-files/dashboards"
GRAFANA_ALERTING_TEMPLATE = (
    "github.com/0xPolygon/kurtosis-cdk/static-files/alerting.yml.tmpl"
)


def run(plan, args):
    prometheus_service = plan.get_service(name="prometheus" + args["deployment_suffix"])
    prometheus_url = "http://{}:{}".format(
        prometheus_service.ip_address, prometheus_service.ports["http"].number
    )

    grafana_alerting_data = {}
    if "slack_alerts" in args:
        grafana_alerting_data = {
            "SlackChannel": args["slack_alerts"]["slack_channel"],
            "SlackToken": args["slack_alerts"]["slack_token"],
            "MentionUsers": args["slack_alerts"]["mention_users"],
        }

    postgres_databases = []
    for db in databases_package.DATABASES.values():
        postgres_databases.append(
            {
                "URL": args["postgres_url"],
                "Name": db["name"],
                "User": db["user"],
                "Password": db["password"],
                "Version": 1500,
            }
        )

    grafana_package.run(
        plan,
        prometheus_url,
        grafana_dashboards_location=GRAFANA_DASHBOARDS,
        name="grafana" + args["deployment_suffix"],
        grafana_version=GRAFANA_VERSION,
        grafana_alerting_template=GRAFANA_ALERTING_TEMPLATE,
        grafana_alerting_data=grafana_alerting_data,
        postgres_databases=postgres_databases,
    )
