databases = import_module("../shared/databases.star")
ports_package = import_module("../shared/ports.star")


# Port identifiers and numbers.
SERVER_PORT_ID = "http"
SERVER_PORT_NUMBER = 8545


def run(plan, args, sequencer_rpc_url):
    deployment_suffix = args.get("deployment_suffix")
    db_configs = databases.get_db_configs(deployment_suffix, args.get("sequencer_type"))
    cdk_erigon_rpc_url = "http://cdk-erigon-rpc{}:{}".format(
        deployment_suffix, ports_package.HTTP_RPC_PORT_NUMBER
    )
    config_artifact = plan.render_templates(
        name="zkevm-pool-manager-config{}".format(args.get("deployment_suffix")),
        config={
            "config.toml": struct(
                template=read_file(
                    src="../../../static_files/chain/cdk-erigon/zkevm-pool-manager/config.toml"
                ),
                data=args
                | {
                    "server_port_number": SERVER_PORT_NUMBER,
                    "sequencer_url": sequencer_rpc_url,
                    "l2_node_url": cdk_erigon_rpc_url,
                }
                | db_configs,
            )
        },
    )

    result = plan.add_service(
        name="zkevm-pool-manager{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("zkevm_pool_manager_image"),
            ports={
                SERVER_PORT_ID: PortSpec(
                    SERVER_PORT_NUMBER, application_protocol="http"
                ),
            },
            files={
                "/etc/pool-manager": Directory(artifact_names=[config_artifact]),
            },
            entrypoint=["/bin/sh", "-c"],
            cmd=[
                "/app/zkevm-pool-manager run --cfg /etc/pool-manager/config.toml",
            ],
        ),
    )
    pool_manager_url = result.ports[SERVER_PORT_ID].url
    return pool_manager_url
