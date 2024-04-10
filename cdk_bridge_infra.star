service_package = import_module("./lib/service.star")
zkevm_agglayer_package = import_module("./lib/zkevm_agglayer.star")
zkevm_bridge_package = import_module("./lib/zkevm_bridge.star")


def run(plan, args):
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)

    # Create the bridge service config.
    bridge_config_artifact = create_bridge_config_artifact(
        plan, args, contract_setup_addresses
    )
    claimtx_keystore_artifact = plan.store_service_files(
        name="claimtxmanager-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/claimtxmanager.keystore",
    )
    bridge_config = zkevm_bridge_package.create_bridge_service_config(
        args, bridge_config_artifact, claimtx_keystore_artifact
    )

    # Create the agglayer service config.
    agglayer_config_artifact = create_agglayer_config_artifact(
        plan, args, contract_setup_addresses
    )
    agglayer_keystore_artifact = plan.store_service_files(
        name="agglayer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/agglayer.keystore",
    )
    agglayer_config = zkevm_agglayer_package.create_agglayer_service_config(
        args, agglayer_config_artifact, agglayer_keystore_artifact
    )

    # Start the bridge service and the agglayer.
    bridge_infra_services = plan.add_services(
        configs=bridge_config | agglayer_config,
        description="Starting bridge infra",
    )

    # Start the bridge UI.
    l1_eth_service = plan.get_service(name="el-1-geth-lighthouse")
    zkevm_node_rpc = plan.get_service(name="zkevm-node-rpc" + args["deployment_suffix"])
    bridge_service_name = "zkevm-bridge-service" + args["deployment_suffix"]
    bridge_service = bridge_infra_services[bridge_service_name]
    config = struct(
        l1_eth_service=l1_eth_service,
        zkevm_rpc_ip_address=zkevm_node_rpc.ip_address,
        zkevm_rpc_http_port=zkevm_node_rpc.ports["http-rpc"],
        bridge_service_ip_address=bridge_service.ip_address,
        bridge_api_http_port=bridge_service.ports["bridge-rpc"],
        zkevm_bridge_address=contract_setup_addresses["zkevm_bridge_address"],
        zkevm_rollup_address=contract_setup_addresses["zkevm_rollup_address"],
        zkevm_rollup_manager_address=contract_setup_addresses[
            "zkevm_rollup_manager_address"
        ],
    )
    zkevm_bridge_package.start_bridge_ui(plan, args, config)


def create_bridge_config_artifact(plan, args, contract_setup_addresses):
    bridge_config_template = read_file(
        src="./templates/bridge-infra/bridge-config.toml"
    )
    return plan.render_templates(
        name="bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # bridge db
                    "zkevm_db_bridge_hostname": args["zkevm_db_bridge_hostname"],
                    "zkevm_db_bridge_name": args["zkevm_db_bridge_name"],
                    "zkevm_db_bridge_user": args["zkevm_db_bridge_user"],
                    "zkevm_db_bridge_password": args["zkevm_db_bridge_password"],
                    # ports
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_bridge_grpc_port": args["zkevm_bridge_grpc_port"],
                    "zkevm_bridge_rpc_port": args["zkevm_bridge_rpc_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                }
                | contract_setup_addresses,
            )
        },
    )


def create_agglayer_config_artifact(plan, args, contract_setup_addresses):
    agglayer_config_template = read_file(
        src="./templates/bridge-infra/agglayer-config.toml"
    )
    return plan.render_templates(
        name="agglayer-config-artifact",
        config={
            "agglayer-config.toml": struct(
                template=agglayer_config_template,
                # TODO: Organize those args.
                data={
                    "deployment_suffix": args["deployment_suffix"],
                    "l1_chain_id": args["l1_chain_id"],
                    "l1_rpc_url": args["l1_rpc_url"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    "zkevm_l2_proofsigner_address": args[
                        "zkevm_l2_proofsigner_address"
                    ],
                    # agglayer db
                    "zkevm_db_agglayer_hostname": args["zkevm_db_agglayer_hostname"],
                    "zkevm_db_agglayer_name": args["zkevm_db_agglayer_name"],
                    "zkevm_db_agglayer_user": args["zkevm_db_agglayer_user"],
                    "zkevm_db_agglayer_password": args["zkevm_db_agglayer_password"],
                    # ports
                    "zkevm_db_postgres_port": args["zkevm_db_postgres_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "zkevm_agglayer_port": args["zkevm_agglayer_port"],
                    "zkevm_prometheus_port": args["zkevm_prometheus_port"],
                }
                | contract_setup_addresses,
            )
        },
    )
