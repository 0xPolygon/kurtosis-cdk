service_package = import_module("../../lib/service.star")

ARPEGGIO_IMAGE = "arpeggio" #TODO: publish image

def run(plan, args):
    arpeggio_config_artifact = get_arpeggio_config(plan, args)
    plan.add_service(
        name="panoptichain" + args["deployment_suffix"],
        config=ServiceConfig(
            image=ARPEGGIO_IMAGE,
            ports={
                "http": HTTP_PROXY_PORT,
                "ws": WS_PROXY_PORT,
                "prometheus": PortSpec(METRICS_PORT, application_protocol="http"),
            },
            files={"/etc/arpeggio": arpeggio_config_artifact},
        ),
    )


def get_arpeggio_config(plan, args):
    arpeggio_config_template = read_file(
        src="../../static_files/additional_services/arpeggio-config/config.yml"
    )
    l2_rpc_urls = service_package.get_l2_rpc_urls(plan, args)
    return plan.render_templates(
        name="arpeggio-config",
        config={
            "config.yml": struct(
                template=arpeggio_config_template,
                data={
                        "l2_rpc_name": args["l2_rpc_name"],
                        "l2_rpc_url": l2_rpc_urls.http,
                        "l2_ws_url": l2_rpc_urls.ws,
                     }
            )
        },
    )
