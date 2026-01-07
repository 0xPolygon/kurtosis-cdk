cdk_erigon_launcher = import_module("./cdk-erigon/launcher.star")
constants = import_module("../package_io/constants.star")
input_parser = import_module("../package_io/input_parser.star")
op_geth_launcher = import_module("./op-geth/launcher.star")
zkevm_bridge_service = import_module("./shared/zkevm_bridge_service.star")
zkevm_bridge_ui = import_module("./shared/zkevm_bridge_ui.star")
zkevm_bridge_proxy = import_module("./shared/zkevm_bridge_proxy.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
    genesis_artifact,
):
    sequencer_type = args.get("sequencer_type")
    if sequencer_type == constants.SEQUENCER_TYPE.cdk_erigon:
        plan.print("Deploying cdk-erigon chain")
        l2_context = cdk_erigon_launcher.launch(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            deployment_stages,
            genesis_artifact,
        )
    elif sequencer_type == constants.SEQUENCER_TYPE.op_geth:
        plan.print("Deploying op-geth chain")
        deploy_cdk_bridge_infra = deployment_stages.get(
            "deploy_cdk_bridge_infra", False
        )
        l2_context = op_geth_launcher.launch(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            deployment_stages,
        )
    else:
        fail(
            "Unsupported sequencer type: '{}', please use one of: '{}'".format(
                sequencer_type, input_parser.VALID_SEQUENCER_TYPES
            )
        )
    l2_rpc_url = l2_context.rpc_url

    # zkevm-bridge-service, bridge-ui and bridge-proxy
    if deployment_stages.get("deploy_cdk_bridge_infra", False):
        zkevm_bridge_service.run(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            l2_rpc_url,
        )

        if deployment_stages.get("deploy_cdk_bridge_ui"):
            zkevm_bridge_ui.run(plan, args, contract_setup_addresses)

            if deployment_stages.get("deploy_l1"):
                zkevm_bridge_proxy.run(plan, args)
