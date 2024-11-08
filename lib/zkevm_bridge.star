ports_package = import_module("../src/package_io/ports.star")


def create_bridge_service_config(args, config_artifact, claimtx_keystore_artifact):
    (ports, public_ports) = get_bridge_service_ports(args)
    return ServiceConfig(
        image=args["zkevm_bridge_service_image"],
        ports=ports,
        public_ports=public_ports,
        files={
            "/etc/zkevm": Directory(
                artifact_names=[config_artifact, claimtx_keystore_artifact]
            ),
        },
        entrypoint=[
            "/app/zkevm-bridge",
        ],
        cmd=["run", "--cfg", "/etc/zkevm/bridge-config.toml"],
    )


def get_bridge_service_ports(args):
    ports = {
        "rpc": PortSpec(args["zkevm_bridge_rpc_port"], application_protocol="http"),
        "grpc": PortSpec(args["zkevm_bridge_grpc_port"], application_protocol="grpc"),
    }
    public_ports = ports_package.get_public_ports(
        ports, "zkevm_bridge_service_start_port", args
    )
    return (ports, public_ports)


def start_bridge_ui(plan, args, config_artifact):
    (ports, public_ports) = get_bridge_ui_ports(args)
    plan.add_service(
        name="zkevm-bridge-ui" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_bridge_ui_image"],
            ports=ports,
            public_ports=public_ports,
            files={
                # It's not possible to mount a file artifact to a persistent directory without
                # removing all the files in this directory. In the case of the bridge ui, copying
                # the .env file artifact to /usr/share/nginx/html will remove the app build.
                # That's why we need this work-around.
                # https://github.com/kurtosis-tech/kurtosis/issues/2111
                "/etc/zkevm": Directory(artifact_names=[config_artifact]),
            },
            entrypoint=["/bin/sh", "-c"],
            cmd=[
                "cp /etc/zkevm/.env /usr/share/nginx/html/.env && nginx -g 'daemon off;'"
            ],
        ),
    )


def get_bridge_ui_ports(args):
    ports = {
        "web-ui": PortSpec(args["zkevm_bridge_ui_port"], application_protocol="http")
    }
    public_ports = ports_package.get_public_ports(
        ports, "zkevm_bridge_ui_start_port", args
    )
    return (ports, public_ports)


def start_reverse_proxy(plan, args, config_artifact):
    (ports, public_ports) = get_revert_proxy_ports(args)
    plan.add_service(
        name="zkevm-bridge-proxy" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_bridge_proxy_image"],
            ports=ports,
            public_ports=public_ports,
            files={
                "/usr/local/etc/haproxy/": Directory(artifact_names=[config_artifact]),
            },
        ),
    )


def get_revert_proxy_ports(args):
    ports = {"web-ui": PortSpec(80, application_protocol="http")}
    public_ports = ports_package.get_public_ports(
        ports, "reverse_proxy_start_port", args
    )
    return (ports, public_ports)
