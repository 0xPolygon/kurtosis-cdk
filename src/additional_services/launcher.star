arpeggio = import_module("./arpeggio.star")
assertoor = import_module("./assertoor.star")
blockscout = import_module("./blockscout.star")
blutgang = import_module("./blutgang.star")
bridge_spammer = import_module("./bridge_spammer.star")
constants = import_module("../package_io/constants.star")
erpc = import_module("./erpc.star")
grafana = import_module("./grafana.star")
panoptichain = import_module("./panoptichain.star")
pless_zkevm_node = import_module("./pless_zkevm_node.star")
prometheus = import_module("./prometheus.star")
status_checker = import_module("./status_checker.star")
test_runner = import_module("./test_runner.star")
tx_spammer = import_module("./tx_spammer.star")


def launch(plan, args, contract_setup_addresses, genesis_artifact):
    for svc in args.get("additional_services", []):
        if svc == constants.ADDITIONAL_SERVICES.arpeggio:
            arpeggio.run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.assertoor:
            assertoor.run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.blockscout:
            blockscout.run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.blutgang:
            blutgang.run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.bridge_spammer:
            bridge_spammer.run(plan, args, contract_setup_addresses)
        elif svc == constants.ADDITIONAL_SERVICES.erpc:
            erpc.run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.pless_zkevm_node:
            # Note that an additional suffix will be added to the permissionless services.
            permissionless_node_args = dict(args)
            permissionless_node_args["original_suffix"] = args["deployment_suffix"]
            permissionless_node_args["deployment_suffix"] = (
                "-pless" + args["deployment_suffix"]
            )
            pless_zkevm_node.run(plan, permissionless_node_args, genesis_artifact)
        elif svc == constants.ADDITIONAL_SERVICES.observability:
            panoptichain.run(plan, args, contract_setup_addresses)
            prometheus.run(plan, args)
            grafana.run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.status_checker:
            status_checker.run(plan, args)
        elif svc == constants.ADDITIONAL_SERVICES.test_runner:
            test_runner.run(plan, args, contract_setup_addresses)
        elif svc == constants.ADDITIONAL_SERVICES.tx_spammer:
            tx_spammer.run(plan, args, contract_setup_addresses)
        else:
            fail("Invalid additional service: %s" % (svc))
