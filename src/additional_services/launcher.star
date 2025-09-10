constants = import_module("../package_io/constants.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    genesis_artifact,
    deployment_stages,
):
    for svc in args.get("additional_services", []):
        if svc == constants.ADDITIONAL_SERVICES.agglogger:
            import_module("./agglogger.star").run(
                plan,
                args,
                contract_setup_addresses,
                sovereign_contract_setup_addresses,
                deployment_stages.get("deploy_optimism_rollup"),
            )
        elif svc == constants.ADDITIONAL_SERVICES.arpeggio:
            import_module("./arpeggio.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.assertoor:
            import_module("./assertoor.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.blockscout:
            import_module("./blockscout.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.blutgang:
            import_module("./blutgang.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.bridge_spammer:
            import_module("./bridge_spammer.star").run(
                plan, args, contract_setup_addresses
            )
        elif svc == constants.ADDITIONAL_SERVICES.erpc:
            import_module("./erpc.star").run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.pless_zkevm_node:
            # Note that an additional suffix will be added to the permissionless services.
            permissionless_node_args = dict(args)
            permissionless_node_args["original_suffix"] = args["deployment_suffix"]
            permissionless_node_args["deployment_suffix"] = (
                "-pless" + args["deployment_suffix"]
            )
            import_module("./pless_zkevm_node.star").run(
                plan, permissionless_node_args, genesis_artifact
            )
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
            )
        elif svc == constants.ADDITIONAL_SERVICES.tx_spammer:
            import_module("./tx_spammer.star").run(plan, args)
        else:
            fail("Invalid additional service: %s" % (svc))
