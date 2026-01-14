ports_package = import_module("../package_io/ports.star")
contracts_util = import_module("../contracts/util.star")

ARPEGGIO_IMAGE = "christophercampbell/arpeggio:v0.0.1"
RPC_PROXY_PORT = 8545
WS_PROXY_PORT = 8546
# METRICS_PORT = 9105


def run(plan, args, l1_context, l2_context):
    arpeggio_config_artifact = plan.render_templates(
        name="arpeggio-config",
        config={
            "config.yml": struct(
                template=read_file(
                    src="../../static_files/additional_services/arpeggio/config.yml"
                ),
                data={
                    "l2_rpc_url": l2_context.rpc_http_url,
                    "l2_ws_url": l2_context.rpc_ws_url,
                },
            )
        },
    )

    plan.add_service(
        name="arpeggio" + args["deployment_suffix"],
        config=ServiceConfig(
            image=ARPEGGIO_IMAGE,
            ports={
                "rpc": PortSpec(RPC_PROXY_PORT, application_protocol="http"),
                "ws": PortSpec(WS_PROXY_PORT, application_protocol="ws"),
                # "prometheus": PortSpec(METRICS_PORT, application_protocol="http"),
            },
            files={"/etc/arpeggio": arpeggio_config_artifact},
        ),
    )
