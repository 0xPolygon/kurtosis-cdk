# Port identifiers and numbers.
SERVER_PORT_ID = "web-ui"
SERVER_PORT_NUMBER = 80


def run(
    plan, args, l1_rpc_url, l2_rpc_url, zkevm_bridge_service_url, zkevm_bridge_ui_url
):
    config_artifact = plan.render_templates(
        name="zkevm-bridge-proxy-config{}".format(args.get("deployment_suffix")),
        config={
            "haproxy.cfg": struct(
                template=read_file(
                    src="../../../static_files/chain/cdk-erigon/zkevm-bridge-proxy/haproxy.cfg"
                ),
                data={
                    "l1_rpc_url": l1_rpc_url,
                    "l2_rpc_url": l2_rpc_url,
                    "zkevm_bridge_service_url": zkevm_bridge_service_url,
                    "zkevm_bridge_ui_url": zkevm_bridge_ui_url,
                },
            )
        },
    )

    plan.add_service(
        name="zkevm-bridge-proxy{}".format(args.get("deployment_suffix")),
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
