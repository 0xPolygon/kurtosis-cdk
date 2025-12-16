databases = import_module("../../../databases.star")


# Port identifiers and numbers.
SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 8545


def run(plan, args):
    name = "zkevm-pool-manager" + args.get("deployment_suffix")

    # Create config.
    deployment_suffix = args.get("deployment_suffix")
    db_configs = databases.get_db_configs(deployment_suffix, args.get("sequencer_type"))
    zkevm_rpc_port = args.get("zkevm_rpc_http_port")
    cdk_erigon_sequencer_url = "http://cdk-erigon-sequencer{}:{}".format(
        deployment_suffix, zkevm_rpc_port
    )
    cdk_erigon_rpc_url = "http://cdk-erigon-rpc{}:{}".format(
        deployment_suffix, zkevm_rpc_port
    )
    config_artifact = plan.render_templates(
        name="pool-manager-config-artifact",
        config={
            "pool-manager-config.toml": struct(
                template=read_file(
                    src="../../../static_files/cdk-erigon/zkevm-pool-manager/config.toml"
                ),
                data=args
                | {
                    "server_hostname": name,
                    "server_port_number": SERVER_PORT_NUMBER,
                    "sequencer_url": cdk_erigon_sequencer_url,
                    "l2_node_url": cdk_erigon_rpc_url,
                }
                | db_configs,
            )
        },
    )

    # Deploy service.
    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=args.get("zkevm_pool_manager_image"),
            ports={
                SERVER_PORT_ID: PortSpec(SERVER_PORT_NUMBER),
            },
            files={
                "/etc/pool-manager": Directory(artifact_names=[config_artifact]),
            },
            entrypoint=["/bin/sh", "-c"],
            cmd=[
                "/app/zkevm-pool-manager run --cfg /etc/pool-manager/pool-manager-config.toml",
            ],
        ),
    )
