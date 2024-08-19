prometheus_package = import_module(
    "github.com/kurtosis-tech/prometheus-package/main.star"
)


def run(plan, args):
    metrics_jobs = get_metrics_jobs(plan)
    prometheus_package.run(
        plan, metrics_jobs, name="prometheus" + args["deployment_suffix"]
    )


def get_metrics_jobs(plan):
    metrics_jobs = []
    for service in plan.get_services():
        if "prometheus" not in service.ports:
            continue

        metrics_path = "/metrics"
        if service.name.startswith("cdk-erigon"):
            metrics_path = "/debug/metrics/prometheus"

        metrics_jobs.append(
            {
                "Name": service.name,
                "Endpoint": "{0}:{1}".format(
                    service.ip_address, service.ports["prometheus"].number
                ),
                "MetricsPath": metrics_path,
            }
        )
    return metrics_jobs
