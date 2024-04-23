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


def run(plan, args):
    for service in plan.get_services():
        if service.name == "zkevm-node-rpc" + args["deployment_suffix"]:
            args["zkevm_rpc_url"] = "http://{}:{}".format(
                service.ip_address, service.ports["http-rpc"].number
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

    # Start grafana.
    grafana_package.run(
        plan,
        prometheus_url,
        "github.com/0xPolygon/kurtosis-cdk/static-files/dashboards",
        name="grafana" + args["deployment_suffix"],
    )
