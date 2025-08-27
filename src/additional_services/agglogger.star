def run(plan, args, contract_setup_addresses, deploy_optimism_rollup):
    l2_rpc_url = service_package.get_l2_rpc_url(plan, args).http

    if deploy_optimism_rollup:
        agglogger_config_template_file = "op-config.json"
    else:
        agglogger_config_template_file = "zkevm-config.json"

    agglogger_config_artifact = plan.render_templates(
        name="agglogger-config",
        config={
            "config.json": struct(
                template=read_file(
                    src="../../static_files/additional_services/agglogger-config/{}".format(
                        agglogger_config_template_file
                    ),
                ),
                data={
                    # l1
                    "l1_rpc_url": args.get("l1_rpc_url"),
                    "l1_chain_id": args.get("l1_chain_id"),
                    # l2
                    "l2_rpc_url": l2_rpc_url,
                    "l2_chain_id": args.get("zkevm_rollup_chain_id"),
                    "l2_network_id": args.get("zkevm_rollup_id"),
                    # agglayer
                    "agglayer_rpc_url": args.get("agglayer_readrpc_url"),
                    # contract addresses
                    "zkevm_rollup_manager_address": contract_setup_addresses.get(
                        "zkevm_rollup_manager_address"
                    ),
                    "zkevm_bridge_address": contract_setup_addresses.get(
                        "zkevm_bridge_address"
                    ),
                    "zkevm_global_exit_root_address": contract_setup_addresses.get(
                        "zkevm_global_exit_root_address"
                    ),
                    "zkevm_global_exit_root_l2_address": contract_setup_addresses.get(
                        "zkevm_global_exit_root_l2_address"
                    ),
                    "sovereign_ger_proxy_addr": contract_setup_addresses.get(
                        "sovereign_ger_proxy_addr"
                    ),
                },
            ),
        },
    )

    plan.add_service(
        name="agglogger" + args["deployment_suffix"],
        config=ServiceConfig(
            image=args.get("agglogger_image"),
            files={
                "/etc/agglogger": Directory(artifact_names=[agglogger_config_artifact]),
            },
            entrypoint=["bash", "-c"],
            cmd=["./agglogger run --config /etc/agglogger/config.json"]
        ),
    )
