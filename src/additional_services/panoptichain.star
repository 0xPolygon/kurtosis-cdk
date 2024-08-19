service_package = import_module("../../lib/service.star")

PANOPTICHAIN_IMAGE = "minhdvu/panoptichain:0.1.47"


def run(plan, args):
    panoptichain_config_artifact = get_panoptichain_config(plan, args)
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
        src="../../static_files/additional_services/panoptichain-config/config.yml"
    )
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    l2_rpc_urls = service_package.get_l2_rpc_urls(plan, args)
    return plan.render_templates(
        name="panoptichain-config",
        config={
            "config.yml": struct(
                template=panoptichain_config_template,
                data={
                    "l1_rpc_url": args["l1_rpc_url"],
                    "l2_rpc_url": l2_rpc_urls.http,
                    "l1_chain_id": args["l1_chain_id"],
                    "zkevm_rollup_chain_id": args["zkevm_rollup_chain_id"],
                }
                | contract_setup_addresses,
            )
        },
    )
