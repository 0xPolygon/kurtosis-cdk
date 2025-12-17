# Port identifiers and numbers.
SERVER_PORT_ID = "web-ui"
SERVER_PORT_NUMBER = 80


def run(plan, args, config_artifact):
    plan.add_service(
        name="zkevm-bridge-ui{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("zkevm_bridge_ui_image"),
            files={
                "/etc/zkevm": Directory(artifact_names=[config_artifact]),
            },
            ports={
                SERVER_PORT_ID: PortSpec(
                    SERVER_PORT_NUMBER,
                    application_protocol="http",
                    wait="60s",
                )
            },
            entrypoint=["/bin/sh", "-c"],
            cmd=[
                "set -a; source /etc/zkevm/.env; set +a; sh /app/scripts/deploy.sh run"
            ],
            # user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )
