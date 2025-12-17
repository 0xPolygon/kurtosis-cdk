constants = import_module("./src/package_io/constants.star")
databases = import_module("./src/chain/shared/databases.star")
zkevm_bridge_service = import_module("./src/chain/shared/zkevm-bridge/service.star")
zkevm_bridge_ui = import_module("./src/chain/shared/zkevm-bridge/ui.star")
zkevm_bridge_proxy = import_module("./src/chain/shared/zkevm-bridge/proxy.star")


def run(
    plan,
    args,
    contract_setup_addresses,
    deploy_bridge_ui=True,
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
    )
    claimsponsor_keystore_artifact = plan.store_service_files(
        name="claimsponsor-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/claimsponsor.keystore",
    )
    zkevm_bridge_service.run(
        plan, args, bridge_config_artifact, claimsponsor_keystore_artifact
    )

    if deploy_bridge_ui:
        # Start the bridge UI.
        bridge_ui_config_artifact = create_bridge_ui_config_artifact(
            plan, args, contract_setup_addresses
        )
        zkevm_bridge_ui.run(plan, args, bridge_ui_config_artifact)

        # Start the bridge UI reverse proxy. This is only relevant / needed if we have a fake l1
        if args["use_local_l1"]:
            proxy_config_artifact = create_reverse_proxy_config_artifact(plan, args)
            zkevm_bridge_proxy.run(plan, args, proxy_config_artifact)


def create_bridge_config_artifact(plan, args, contract_setup_addresses, db_configs):
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
            and args["sequencer_type"] == constants.SEQUENCER_TYPE.op_geth
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
                    "log_level": args.get("log_level"),
                    "environment": args.get("environment"),
                    "l2_keystore_password": args["l2_keystore_password"],
                    "db": db_configs.get("bridge_db"),
                    "require_sovereign_chain_contract": require_sovereign_chain_contract,
                    "sequencer_type": args["sequencer_type"],
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
