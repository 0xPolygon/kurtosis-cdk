# Port identifiers and numbers.
SERVER_PORT_ID = "web-ui"
SERVER_PORT_NUMBER = 80


def run(plan, args, config_artifact):
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
