cdk_erigon_launcher = "./cdk-erigon/launcher.star"
constants = "../package_io/constants.star"
input_parser = "../../input_parser.star"
op_geth_launcher = "./op-geth/launcher.star"


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
        cdk_erigon_launcher.launch(
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
        deploy_op_succinct = deployment_stages.get("deploy_op_succinct", False)
        op_geth_launcher.launch(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            deploy_cdk_bridge_infra,
            deploy_op_succinct,
        )
    else:
        fail(
            "Unsupported sequencer type: '{}', please use one of: '{}'".format(
                sequencer_type, input_parser.VALID_SEQUENCER_TYPES
            )
        )
