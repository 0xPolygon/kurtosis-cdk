BLUTGANG_IMAGE = "makemake1337/blutgang:0.3.6"

RPC_PORT_ID = "rpc"
RPC_PORT_NUMBER = 8555

ADMIN_PORT_ID = "admin"
ADMIN_PORT_NUMBER = 8556


def run(plan, l2_context):
    blutgang_config_artifact = plan.render_templates(
        name="blutgang-config" + l2_context.name,
        config={
            "config.toml": struct(
                template=read_file(
                    src="../../static_files/additional_services/blutgang/config.toml"
                ),
                data={
                    # ports
                    "rpc_port_number": RPC_PORT_NUMBER,
                    "admin_port_number": ADMIN_PORT_NUMBER,
                    # urls
                    "l2_sequencer_url": l2_context.sequencer_url,
                    "l2_rpc_url": l2_context.rpc_http_url,
                    "l2_ws_url": l2_context.rpc_ws_url,
                },
            )
        },
    )

    plan.add_service(
        name="blutgang" + l2_context.name,
        config=ServiceConfig(
            image=BLUTGANG_IMAGE,
            ports={
                RPC_PORT_ID: PortSpec(RPC_PORT_NUMBER, application_protocol="http"),
                ADMIN_PORT_ID: PortSpec(ADMIN_PORT_NUMBER, application_protocol="http"),
            },
            files={
                "/etc/blutgang": Directory(
                    artifact_names=[
                        blutgang_config_artifact,
                    ]
                ),
            },
            cmd=["/app/blutgang", "-c", "/etc/blutgang/config.toml"],
        ),
    )
