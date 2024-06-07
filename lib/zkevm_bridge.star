def create_bridge_service_config(args, config_artifact, claimtx_keystore_artifact):
    bridge_service_name = "zkevm-bridge-service" + args["deployment_suffix"]
    bridge_service_config = ServiceConfig(
        image=args["zkevm_bridge_service_image"],
        ports={
            "rpc": PortSpec(args["zkevm_bridge_rpc_port"], application_protocol="http"),
            "grpc": PortSpec(
                args["zkevm_bridge_grpc_port"], application_protocol="grpc"
            ),
        },
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
    return {bridge_service_name: bridge_service_config}


def start_bridge_ui(plan, args, config_artifact):
    plan.add_service(
        name="zkevm-bridge-ui" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_bridge_ui_image"],
            ports={
                "web-ui": PortSpec(
                    args["zkevm_bridge_ui_port"], application_protocol="http"
                ),
            },
            files={
                "/etc/zkevm": Directory(artifact_names=[config_artifact]),
            },
            entrypoint=["/bin/sh", "-c"],
            cmd=[
                "set -a; source /etc/zkevm/.env; set +a; sh /app/scripts/deploy.sh run"
            ],
            # user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )


def start_reverse_proxy(plan, args, config_artifact):
    plan.add_service(
        name="zkevm-bridge-proxy" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args["zkevm_bridge_proxy_image"],
            ports={
                "web-ui": PortSpec(
                    number=80,
                    application_protocol="http",
                ),
            },
            files={
                "/usr/local/etc/haproxy/": Directory(artifact_names=[config_artifact]),
            },
        ),
    )
