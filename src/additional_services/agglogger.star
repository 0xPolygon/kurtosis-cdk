constants = import_module("../package_io/constants.star")
contracts_util = import_module("../contracts/util.star")


def run(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    sequencer_type,
):
    l2_rpc_url = contracts_util.get_l2_rpc_url(plan, args).http

    if sequencer_type == constants.SEQUENCER_TYPE.op_geth:
        agglogger_config_template_file = "op-config.json"
    else:
        agglogger_config_template_file = "zkevm-config.json"

    agglogger_config_artifact = plan.render_templates(
        name="agglogger-config{}".format(args.get("deployment_suffix")),
        config={
            "config.json": struct(
                template=read_file(
                    src="../../static_files/additional_services/agglogger/{}".format(
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
                    "rollup_manager_address": contract_setup_addresses.get(
                        "rollup_manager_address"
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
                    "sovereign_ger_proxy_addr": sovereign_contract_setup_addresses.get(
                        "sovereign_ger_proxy_addr"
                    ),
                },
            ),
        },
    )

    plan.add_service(
        name="agglogger{}".format(args.get("deployment_suffix")),
        config=ServiceConfig(
            image=args.get("agglogger_image"),
            files={
                "/etc/agglogger": Directory(artifact_names=[agglogger_config_artifact]),
            },
            entrypoint=["sh", "-c"],
            cmd=["./agglogger run --config /etc/agglogger/config.json", "2>&1"],
        ),
    )
