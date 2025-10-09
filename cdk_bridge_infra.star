constants = import_module("./src/package_io/constants.star")
databases = import_module("./databases.star")
zkevm_bridge_package = import_module("./lib/zkevm_bridge.star")


def run(
    plan,
    args,
    contract_setup_addresses,
    deploy_bridge_ui=True,
    deploy_optimism_rollup=False,
):
    db_configs = databases.get_db_configs(
        args["deployment_suffix"], args["sequencer_type"]
    )

    # Start the bridge service.
    bridge_config_artifact = create_bridge_config_artifact(
        plan,
        args,
        contract_setup_addresses,
        db_configs,
        deploy_optimism_rollup,
    )
    claimtx_keystore_artifact = plan.store_service_files(
        name="claimtxmanager-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/claimtxmanager.keystore",
    )
    bridge_service_config = zkevm_bridge_package.create_bridge_service_config(
        args, bridge_config_artifact, claimtx_keystore_artifact
    )
    plan.add_service(
        name="zkevm-bridge-service" + args["deployment_suffix"],
        config=bridge_service_config,
    )

    if deploy_bridge_ui:
        # Start the bridge UI.
        bridge_ui_config_artifact = create_bridge_ui_config_artifact(
            plan, args, contract_setup_addresses
        )
        zkevm_bridge_package.start_bridge_ui(plan, args, bridge_ui_config_artifact)

        # Start the bridge UI reverse proxy. This is only relevant / needed if we have a fake l1
        if args["use_local_l1"]:
            proxy_config_artifact = create_reverse_proxy_config_artifact(plan, args)
            zkevm_bridge_package.start_reverse_proxy(plan, args, proxy_config_artifact)


def create_bridge_config_artifact(
    plan, args, contract_setup_addresses, db_configs, deploy_optimism_rollup
):
    bridge_config_template = read_file(
        src="./templates/bridge-infra/bridge-config.toml"
    )
    l1_rpc_url = args["mitm_rpc_url"].get("bridge", args["l1_rpc_url"])
    l2_rpc_url = "http://{}{}:{}".format(
        args["l2_rpc_name"], args["deployment_suffix"], args["zkevm_rpc_http_port"]
    )

    consensus_contract_type = args["consensus_contract_type"]
    require_sovereign_chain_contract = (
        (
            consensus_contract_type == constants.CONSENSUS_TYPE.pessimistic
            and deploy_optimism_rollup
        )
        or consensus_contract_type == constants.CONSENSUS_TYPE.ecdsa_multisig
        or consensus_contract_type == constants.CONSENSUS_TYPE.fep
    )

    return plan.render_templates(
        name="bridge-config-artifact",
        config={
            "bridge-config.toml": struct(
                template=bridge_config_template,
                data={
                    "log_level": args["log_level"],
                    "zkevm_l2_keystore_password": args["zkevm_l2_keystore_password"],
                    "db": db_configs.get("bridge_db"),
                    "require_sovereign_chain_contract": require_sovereign_chain_contract,
                    # rpc urls
                    "l1_rpc_url": l1_rpc_url,
                    "l2_rpc_url": l2_rpc_url,
                    # ports
                    "grpc_port_number": args["zkevm_bridge_grpc_port"],
                    "rpc_port_number": args["zkevm_bridge_rpc_port"],
                    "metrics_port_number": args["zkevm_bridge_metrics_port"],
                }
                | contract_setup_addresses,
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

    l1_rpc_url = args["mitm_rpc_url"].get("bridge", args["l1_rpc_url"])
    l1rpc_host = l1_rpc_url.split(":")[1].replace("//", "")
    l1rpc_port = l1_rpc_url.split(":")[2]
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
