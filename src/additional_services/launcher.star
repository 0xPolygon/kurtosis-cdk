constants = import_module("../package_io/constants.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    genesis_artifact,
    deployment_stages,
    sequencer_type,
    l1_context,
    l2_context,
):
    for svc in args.get("additional_services", []):
        if svc == constants.ADDITIONAL_SERVICES.agglogger:
            import_module("./agglogger.star").run(
                plan,
                args,
                contract_setup_addresses,
                sovereign_contract_setup_addresses,
                sequencer_type,
            )
        elif svc == constants.ADDITIONAL_SERVICES.arpeggio:
            import_module("./arpeggio.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.assertoor:
            import_module("./assertoor.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.blockscout:
            import_module("./blockscout.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.blutgang:
            import_module("./blutgang.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.bridge_hub_api:
            api_url = import_module("./bridge_hub/api.star").run(
                plan, args, contract_setup_addresses, l2_context
            )
            import_module("./bridge_hub/ui.star").run(
                plan, args, contract_setup_addresses, l1_context, l2_context, api_url
            )
        elif svc == constants.ADDITIONAL_SERVICES.bridge_spammer:
            import_module("./bridge_spammer.star").run(
                plan, args, contract_setup_addresses
            )
        elif svc == constants.ADDITIONAL_SERVICES.erpc:
            import_module("./erpc.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.observability:
            import_module("./panoptichain.star").run(
                plan, args, contract_setup_addresses
            )
            import_module("./prometheus.star").run(plan, args)
            import_module("./grafana.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.rpc_fuzzer:
            import_module("./rpc_fuzzer.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.status_checker:
            import_module("./status_checker.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.test_runner:
            import_module("./test_runner.star").run(
                plan,
                args,
                contract_setup_addresses,
                sovereign_contract_setup_addresses,
                deployment_stages,
                sequencer_type,
            )
        elif svc == constants.ADDITIONAL_SERVICES.tx_spammer:
            import_module("./tx_spammer.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.agglayer_dashboard:
            import_module("./agglayer_dashboard.star").run(
                plan, args, contract_setup_addresses
            )
        elif svc == constants.ADDITIONAL_SERVICES.zkevm_bridge_ui:
            zkevm_bridge_ui_url = import_module("./zkevm_bridge_ui/server.star").run(
                plan, args, contract_setup_addresses
            )

            if deployment_stages.get("deploy_l1"):
                import_module("./zkevm_bridge_ui/proxy.star").run(
                    plan,
                    args,
                    l1_context.rpc_url,
                    l2_context.rpc_url,
                    l2_context.zkevm_bridge_service_url,
                    zkevm_bridge_ui_url,
                )
        else:
            fail("Invalid additional service: %s" % (svc))
