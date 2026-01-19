ASSERTOOR_IMAGE = "ethpandaops/assertoor:v0.0.11"

SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 8080


def run(plan, args, l1_context, l2_context):
    assertoor_config_artifact = plan.render_templates(
        name="assertoor-config" + l2_context.name,
        config={
            "config.yaml": struct(
                template=read_file(
                    src="../../static_files/additional_services/assertoor/config.yaml"
                ),
                data={
                    "l1_el_rpc_url": l1_context.el_rpc_url,
                    "l1_cl_rpc_url": l1_context.cl_rpc_url,
                    "server_port_number": SERVER_PORT_NUMBER,
                },
            )
        },
    )

    plan.add_service(
        name="assertoor" + l2_context.name,
        config=ServiceConfig(
            image=ASSERTOOR_IMAGE,
            ports={
                SERVER_PORT_ID: PortSpec(
                    number=SERVER_PORT_NUMBER,
                    transport_protocol="tcp",
                    application_protocol="http",
                )
            },
            files={
                "/config": assertoor_config_artifact,
                "/validator-ranges": "validator-ranges",
            },
            cmd=["--config", "/config/config.yaml"],
        ),
    )
