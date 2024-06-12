service_package = import_module("./lib/service.star")
zkevm_agglayer_package = import_module("./lib/zkevm_agglayer.star")
zkevm_bridge_package = import_module("./lib/zkevm_bridge.star")
databases = import_module("./databases.star")


def run(plan, args):
    contract_setup_addresses = service_package.get_contract_setup_addresses(plan, args)
    db_configs = databases.get_db_configs(args["deployment_suffix"])

    # Create the bridge service config.
    bridge_config_artifact = create_bridge_config_artifact(
        plan, args, contract_setup_addresses, db_configs
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
        plan, args, contract_setup_addresses, db_configs
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
    bridge_ui_config_artifact = create_bridge_ui_config_artifact(
        plan, args, contract_setup_addresses
    )
    zkevm_bridge_package.start_bridge_ui(plan, args, bridge_ui_config_artifact)

    # Start the bridge UI reverse proxy.
    proxy_config_artifact = create_reverse_proxy_config_artifact(plan, args)
    zkevm_bridge_package.start_reverse_proxy(plan, args, proxy_config_artifact)


def create_agglayer_config_artifact(plan, args, contract_setup_addresses, db_configs):
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
                    # ports
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                    "zkevm_agglayer_port": args["zkevm_agglayer_port"],
                    "zkevm_prometheus_port": args["zkevm_prometheus_port"],
                    "l2_rpc_name": args["l2_rpc_name"],
                }
                | contract_setup_addresses
                | db_configs,
            )
        },
    )


def create_bridge_config_artifact(plan, args, contract_setup_addresses, db_configs):
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
                    "l2_rpc_name": args["l2_rpc_name"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    # ports
                    "zkevm_bridge_grpc_port": args["zkevm_bridge_grpc_port"],
                    "zkevm_bridge_rpc_port": args["zkevm_bridge_rpc_port"],
                    "zkevm_rpc_http_port": args["zkevm_rpc_http_port"],
                }
                | contract_setup_addresses
                | db_configs,
            )
        },
    )


def create_bridge_ui_config_artifact(plan, args, contract_setup_addresses):
    bridge_ui_config_template = read_file("./templates/bridge-infra/.env")
    return plan.render_templates(
        name="bridge-ui-config-artifact",
        config={
            ".env": struct(
                template=bridge_ui_config_template,
                data={
                    "l1_explorer_url": args["l1_explorer_url"],
                    "zkevm_explorer_url": args["polygon_zkevm_explorer"],
                }
                | contract_setup_addresses,
            )
        },
    )


def create_reverse_proxy_config_artifact(plan, args):
    bridge_ui_proxy_config_template = read_file(
        src="./templates/bridge-infra/haproxy.cfg"
    )

    l1rpc_service = plan.get_service("el-1-geth-lighthouse")
    l2rpc_service = plan.get_service(
        name=args["l2_rpc_name"] + args["deployment_suffix"]
    )
    bridge_service = plan.get_service(
        name="zkevm-bridge-service" + args["deployment_suffix"]
    )
    bridgeui_service = plan.get_service(
        name="zkevm-bridge-ui" + args["deployment_suffix"]
    )

    return plan.render_templates(
        name="bridge-ui-proxy",
        config={
            "haproxy.cfg": struct(
                template=bridge_ui_proxy_config_template,
                data={
                    "l1rpc_ip": l1rpc_service.ip_address,
                    "l1rpc_port": l1rpc_service.ports["rpc"].number,
                    "l2rpc_ip": l2rpc_service.ip_address,
                    "l2rpc_port": l2rpc_service.ports["http-rpc"].number,
                    "bridgeservice_ip": bridge_service.ip_address,
                    "bridgeservice_port": bridge_service.ports["rpc"].number,
                    "bridgeui_ip": bridgeui_service.ip_address,
                    "bridgeui_port": bridgeui_service.ports["web-ui"].number,
                },
            )
        },
    )
