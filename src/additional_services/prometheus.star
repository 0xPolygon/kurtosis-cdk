prometheus_package = import_module(
    "github.com/kurtosis-tech/prometheus-package/main.star@v1.1.0"
)

PROMETHEUS_IMAGE = "prom/prometheus:v3.0.1"


def run(plan, args):
    metrics_jobs = get_metrics_jobs(plan)
    prometheus_package.run(
        plan,
        metrics_jobs,
        name="prometheus" + args["deployment_suffix"],
        min_cpu=10,
        max_cpu=1000,
        min_memory=128,
        max_memory=2048,
        node_selectors=None,
        storage_tsdb_retention_time="1d",
        storage_tsdb_retention_size="512MB",
        image=PROMETHEUS_IMAGE,
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
