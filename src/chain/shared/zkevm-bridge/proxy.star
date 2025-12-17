# Port identifiers and numbers.
SERVER_PORT_ID = "web-ui"
SERVER_PORT_NUMBER = 80


def run(plan, args):
    l1_rpc_url = args["mitm_rpc_url"].get("bridge", args.get("l1_rpc_url"))
    l1rpc_host = l1_rpc_url.split(":")[1].replace("//", "")
    l1rpc_port = l1_rpc_url.split(":")[2]
    l2rpc_service = plan.get_service(
        name=args.get("l2_rpc_name") + args.get("deployment_suffix")
    )
    bridge_service = plan.get_service(
        name="zkevm-bridge-service" + args.get("deployment_suffix")
    )
    bridgeui_service = plan.get_service(
        name="zkevm-bridge-ui" + args.get("deployment_suffix")
    )
    config_artifact = plan.render_templates(
        name="zkevm-bridge-proxy",
        config={
            "haproxy.cfg": struct(
                template=read_file(
                    src="../../../static_files/zkevm-bridge/proxy/haproxy.cfg"
                ),
                data={
                    "l1rpc_ip": l1rpc_host,
                    "l1rpc_port": l1rpc_port,
                    "l2rpc_ip": l2rpc_service.ip_address,
                    "l2rpc_port": l2rpc_service.ports["rpc"].number,
                    "bridgeservice_ip": bridge_service.ip_address,
                    "bridgeservice_port": bridge_service.ports["rpc"].number,
                    "bridgeui_ip": bridgeui_service.ip_address,
                    "bridgeui_port": bridgeui_service.ports["web-ui"].number,
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
