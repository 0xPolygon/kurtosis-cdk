prometheus_package = import_module(
    "github.com/kurtosis-tech/prometheus-package/main.star"
)
grafana_package = import_module("github.com/kurtosis-tech/grafana-package/main.star")


def start_panoptichain(plan, args):
    # Create the panoptichain config.
    panoptichain_config_template = read_file(src="../templates/panoptichain-config.yml")
    panoptichain_config_artifact = plan.render_templates(
        name="panoptichain-config",
        config={
            "config.yml": struct(
                template=panoptichain_config_template,
                data=args,
            )
        },
    )

    # Start panoptichain.
    return plan.add_service(
        name="panoptichain" + args["deployment_suffix"],
        config=ServiceConfig(
            image="minhdvu/panoptichain",
            ports={
                "prometheus": PortSpec(9090, application_protocol="http"),
            },
            files={"/etc/panoptichain": panoptichain_config_artifact},
        ),
    )


def run(plan, args, services):
    services.append(start_panoptichain(plan, args))

    metrics_jobs = [
        {
            "Name": service.name,
            "Endpoint": "{0}:{1}".format(
                service.ip_address,
                service.ports["prometheus"].number,
            ),
        }
        for service in services
    ]

    # Start prometheus.
    prometheus_url = prometheus_package.run(plan, metrics_jobs)

    # Start grafana.
    grafana_package.run(
        plan,
        prometheus_url,
        "github.com/0xPolygon/kurtosis-cdk/static-files/dashboards",
    )
