constants = import_module("../../package_io/constants.star")


# Port identifiers and numbers.
SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 80


def run(plan, args, contract_setup_addresses, l1_context, l2_context, api_url):
    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")
    web_ui_url = run_server(plan, args, contract_setup_addresses)
    run_proxy(
        plan,
        args,
        l1_context.rpc_url,
        l2_context.rpc_url,
        api_url,
        web_ui_url,
    )


def run_server(plan, args, contract_setup_addresses):
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
                    "l1_bridge_address": l1_bridge_address,
                    # l2
                    "l2_chain_id": args.get("l2_chain_id"),
                    "l2_network_id": args.get("l2_network_id"),
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
                "BRIDGE_HUB_API_URL": "/bridgehubapi",
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


def run_proxy(
    plan, args, l1_rpc_url, l2_rpc_url, bridge_hub_api_url, agglayer_dev_ui_url
):
    config_artifact = plan.render_templates(
        name="agglayer-dev-ui-proxy-config{}".format(args.get("deployment_suffix")),
        config={
            "haproxy.cfg": struct(
                template=read_file(
                    src="../../../static_files/additional_services/bridge-hub/proxy/haproxy.cfg"
                ),
                data={
                    "l1_rpc_url": l1_rpc_url.removeprefix("http://"),
                    "l2_rpc_url": l2_rpc_url.removeprefix("http://"),
                    "bridge_hub_api_url": bridge_hub_api_url.removeprefix("http://"),
                    "agglayer_dev_ui_url": agglayer_dev_ui_url.removeprefix("http://"),
                },
            )
        },
    )

    plan.add_service(
        name="agglayer-dev-ui-proxy{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("zkevm_bridge_proxy_image"),
            files={
                "/usr/local/etc/haproxy/": Directory(artifact_names=[config_artifact]),
            },
            ports={
                SERVER_PORT_ID: PortSpec(
                    SERVER_PORT_NUMBER, application_protocol="http"
                )
            },
        ),
    )
