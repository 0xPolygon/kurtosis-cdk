aggkit_package = import_module("../../aggkit.star")
agglayer_contracts_package = "../../agglayer_contracts.star"
cdk_central_environment_package = "../../cdk_central_environment.star"
cdk_bridge_infra_package = "../../cdk_bridge_infra.star"
cdk_erigon_package = "../../cdk_erigon.star"
constants = "../../package_io/constants.star"
zkevm_pool_manager_package = "../../zkevm_pool_manager.star"


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
    genesis_artifact,
):
    plan.print("Deploying cdk-erigon sequencer")
    import_module(cdk_erigon_package).run_sequencer(
        plan,
        args
        | {
            "l1_rpc_url": args["mitm_rpc_url"].get(
                "erigon-sequencer", args["l1_rpc_url"]
            )
        },
        contract_setup_addresses,
    )

    plan.print("Deploying zkevm-pool-manager")
    import_module(zkevm_pool_manager_package).run_zkevm_pool_manager(plan, args)

    plan.print("Deploying cdk-erigon node")
    import_module(cdk_erigon_package).run_rpc(
        plan,
        args
        | {"l1_rpc_url": args["mitm_rpc_url"].get("erigon-rpc", args["l1_rpc_url"])},
        contract_setup_addresses,
    )

    args["genesis_artifact"] = genesis_artifact

    consensus_type = args.get("consensus_type")
    if consensus_type in [
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
    ]:
        plan.print("Deploying cdk-node")
        import_module(cdk_central_environment_package).run(
            plan, args, contract_setup_addresses
        )

    if deployment_stages.get("deploy_aggkit_node", False):
        plan.print("Deploying aggkit (cdk node)")
        import_module(aggkit_package).run_aggkit_cdk_node(
            plan,
            args,
            contract_setup_addresses,
        )

    # fund account on L2
    import_module(agglayer_contracts_package).l2_legacy_fund_accounts(plan, args)

    # Deploy cdk/bridge infrastructure only if using CDK Node instead of Aggkit. This can be inferred by the consensus_contract_type.
    deploy_cdk_bridge_infra = deployment_stages.get("deploy_cdk_bridge_infra", False)
    if deploy_cdk_bridge_infra and (
        consensus_type
        in [
            constants.CONSENSUS_TYPE.rollup,
            constants.CONSENSUS_TYPE.cdk_validium,
        ]
    ):
        plan.print("Deploying cdk/bridge infrastructure")
        import_module(cdk_bridge_infra_package).run(
            plan,
            args | {"use_local_l1": deployment_stages.get("deploy_l1", False)},
            contract_setup_addresses,
            deployment_stages.get("deploy_cdk_bridge_ui", True),
        )

    # Deploy aggkit infrastructure + dedicated bridge service
    if consensus_type in [
        constants.CONSENSUS_TYPE.pessimistic,
        constants.CONSENSUS_TYPE.ecdsa_multisig,
    ]:
        plan.print("Deploying aggkit infrastructure")
        aggkit_package.run(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            deploy_cdk_bridge_infra,
            False,
        )
