constants = import_module("../../package_io/constants.star")


# Port identifiers and numbers.
SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 80


def run(plan, args, contract_setup_addresses, l2_context, api_url):
    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")
    config_artifact = plan.render_templates(
        name="agglayer-dev-ui-config",
        config={
            "config.ts": struct(
                template=read_file(
                    src="../../../static_files/additional_services/bridge-hub/server/config.ts.tmpl",
                ),
                data={
                    # l1
                    "l1_chain_id": args.get("l1_chain_id"),
                    "l1_rpc_url": args.get("l1_rpc_url"),
                    "l1_bridge_address": l1_bridge_address,
                    # l2
                    "l2_chain_id": args.get("l2_chain_id"),
                    "l2_network_id": args.get("l2_network_id"),
                    "l2_rpc_url": l2_context.rpc_url,
                },
            ),
        },
    )

    result = plan.add_service(
        name="agglayer-dev-ui",
        config=ServiceConfig(
            image=constants.DEFAULT_IMAGES.get("agglayer_dev_ui_image"),
            files={
                "/etc/agglayer-dev-ui": Directory(artifact_names=[config_artifact]),
            },
            env_vars={
                "BRIDGE_HUB_API_URL": api_url,
            },
            ports={
                SERVER_PORT_ID: PortSpec(
                    number=SERVER_PORT_NUMBER, application_protocol="http"
                )
            },
        ),
    )
    server_url = result.ports[SERVER_PORT_ID].url
    return server_url
