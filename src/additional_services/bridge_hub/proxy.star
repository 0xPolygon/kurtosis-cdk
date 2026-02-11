# Port identifiers and numbers.
SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 80


def run(plan, args, l1_rpc_url, l2_rpc_url, bridge_hub_api_url, agglayer_dev_ui_url):
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
