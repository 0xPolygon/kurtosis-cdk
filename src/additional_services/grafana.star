databases_package = import_module("../chain/shared/databases.star")
grafana_package = import_module(
    "github.com/kurtosis-tech/grafana-package/main.star@cc66468b167d16c0fc7153980be5b67550be01be"
)

GRAFANA_VERSION = "11.1.4"
GRAFANA_DASHBOARDS = "github.com/0xPolygon/kurtosis-cdk/static_files/additional_services/grafana-config/dashboards"
GRAFANA_ALERTING_TEMPLATE = "github.com/0xPolygon/kurtosis-cdk/static_files/additional_services/grafana-config/alerting.yml.tmpl"

SLACK_CHANNEL = ""
SLACK_TOKEN = ""
SLACK_MENTION_USERS = ""


def run(plan, args):
    prometheus_service = plan.get_service(name="prometheus" + args["deployment_suffix"])
    prometheus_url = "http://{}:{}".format(
        prometheus_service.ip_address, prometheus_service.ports["http"].number
    )

    grafana_alerting_data = {
        "SlackChannel": SLACK_CHANNEL,
        "SlackToken": SLACK_TOKEN,
        "MentionUsers": SLACK_MENTION_USERS,
    }

    postgres_databases = []
    postgres_service = plan.get_service(
        databases_package.POSTGRES_SERVICE_NAME + args["deployment_suffix"]
    )
    postgres_url = "{}:{}".format(
        postgres_service.ip_address, postgres_service.ports["postgres"].number
    )
    for db in databases_package.DATABASES.values():
        postgres_databases.append(
            {
                "URL": postgres_url,
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
