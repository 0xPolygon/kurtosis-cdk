ARPEGGIO_IMAGE = "christophercampbell/arpeggio:v0.0.1"

RPC_PROXY_PORT_ID = "rpc"
RPC_PROXY_PORT_NUMBER = 8545

WS_PROXY_PORT_ID = "ws"
WS_PROXY_PORT_NUMBER = 8546


def run(plan, l1_context, l2_context):
    arpeggio_config_artifact = plan.render_templates(
        name="arpeggio-config" + l2_context.name,
        config={
            "config.yml": struct(
                template=read_file(
                    src="../../static_files/additional_services/arpeggio/config.yml"
                ),
                data={
                    "name": "l2{}-rpc".format(l2_context.name),
                    "l2_rpc_url": l2_context.rpc_http_url,
                    "l2_ws_url": l2_context.rpc_ws_url,
                },
            )
        },
    )

    plan.add_service(
        name="arpeggio" + l2_context.name,
        config=ServiceConfig(
            image=ARPEGGIO_IMAGE,
            ports={
                RPC_PROXY_PORT_ID: PortSpec(
                    RPC_PROXY_PORT_NUMBER, application_protocol="http"
                ),
                WS_PROXY_PORT_ID: PortSpec(
                    WS_PROXY_PORT_NUMBER, application_protocol="ws"
                ),
            },
            files={"/etc/arpeggio": arpeggio_config_artifact},
        ),
    )
