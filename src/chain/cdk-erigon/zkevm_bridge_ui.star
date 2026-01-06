# Port identifiers and numbers.
SERVER_PORT_ID = "web-ui"
SERVER_PORT_NUMBER = 80


def run(plan, args, contract_setup_addresses):
    config_artifact = plan.render_templates(
        name="zkevm-bridge-ui-config{}".format(args.get("deployment_suffix")),
        config={
            ".env": struct(
                template=read_file(
                    "../../../static_files/cdk-erigon/zkevm-bridge-ui/.env"
                ),
                data={
                    "l1_explorer_url": args["l1_explorer_url"],
                    "zkevm_explorer_url": args["polygon_zkevm_explorer"],
                }
                | contract_setup_addresses,
            )
        },
    )

    result = plan.add_service(
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
    server_url = result.ports[SERVER_PORT_ID].number
    return server_url
