service_package = import_module("../..lib/service.star")

PANOPTICHAIN_IMAGE = "minhdvu/panoptichain:0.1.47"


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

    panoptichain_config = get_panoptichain_config(plan, args)
    plan.add_service(
        name="panoptichain" + args["deployment_suffix"],
        config=ServiceConfig(
            image=PANOPTICHAIN_IMAGE,
            ports={
                "prometheus": PortSpec(9090, application_protocol="http"),
            },
            files={"/etc/panoptichain": panoptichain_config_artifact},
        ),
    )


def get_panoptichain_config(plan, args):
    panoptichain_config_template = read_file(
        src="../../templates/observability/panoptichain-config.yml"
    )
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    return plan.render_templates(
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
