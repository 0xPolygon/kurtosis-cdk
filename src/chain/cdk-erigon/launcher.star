aggkit_package = import_module("../shared/aggkit.star")
agglayer_contracts_package = import_module("../../contracts/agglayer.star")
cdk_erigon = import_module("./cdk_erigon.star")
cdk_node = import_module("./cdk_node.star")
constants = import_module("../../package_io/constants.star")
databases = import_module("../shared/databases.star")
cdk_data_availability = import_module("./cdk_data_availability.star")
ports_package = import_module("../shared/ports.star")
zkevm_pool_manager = import_module("./zkevm_pool_manager.star")
zkevm_prover = import_module("./zkevm_prover.star")
zkevm_bridge_service = import_module("../shared/zkevm_bridge_service.star")
zkevm_bridge_ui = import_module("./zkevm_bridge_ui.star")
zkevm_bridge_proxy = import_module("./zkevm_bridge_proxy.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
    genesis_artifact,
):
    consensus_type = args.get("consensus_contract_type")

    # cdk-data-availability
    # required to be up before setting the data availability committee (contracts)
    if consensus_type == constants.CONSENSUS_TYPE.cdk_validium:
        cdk_data_availability.run(plan, args, contract_setup_addresses)

    if consensus_type in [
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
    ]:
        # cdk-node
        cdk_node_context = cdk_node.run(
            plan, args, contract_setup_addresses, genesis_artifact
        )
        aggregator_url = cdk_node_context.aggregator_url

        # zkevm-prover
        if not args.get("zkevm_use_real_verifier") and not args.get("enable_normalcy"):
            zkevm_prover.run_prover(plan, args, aggregator_url)

    # stateless executor
    stateless_executor_url = None
    if args.get("erigon_strict_mode"):
        stateless_executor_context = zkevm_prover.run_stateless_executor(plan, args)
        stateless_executor_url = stateless_executor_context.executor_url

    # cdk-erigon sequencer
    sequencer_context = cdk_erigon.run_sequencer(
        plan,
        args
        | {
            "l1_rpc_url": args["mitm_rpc_url"].get(
                "erigon-sequencer", args["l1_rpc_url"]
            )
        },
        contract_setup_addresses,
        stateless_executor_url if stateless_executor_url else None,
    )
    sequencer_rpc_url = sequencer_context.http_rpc_url
    datastreamer_url = sequencer_context.datastreamer_url

    # zkevm-pool-manager
    pool_manager_url = zkevm_pool_manager.run(plan, args, sequencer_rpc_url)

    # cdk-erigon rpc
    rpc_context = cdk_erigon.run_rpc(
        plan,
        args
        | {"l1_rpc_url": args["mitm_rpc_url"].get("erigon-rpc", args["l1_rpc_url"])},
        contract_setup_addresses,
        sequencer_rpc_url,
        datastreamer_url,
        pool_manager_url,
    )
    rpc_url = rpc_context.http_rpc_url

    # aggkit: ???
    if deployment_stages.get("deploy_aggkit_node"):
        plan.print("Deploying aggkit")
        aggkit_package.run_aggkit_cdk_node(
            plan,
            args,
            contract_setup_addresses,
        )

    # fund cdk-erigon account on L2
    agglayer_contracts_package.l2_legacy_fund_accounts(plan, args)

    # Deploy cdk/bridge infrastructure only if using CDK Node instead of Aggkit. This can be inferred by the consensus_contract_type.
    deploy_cdk_bridge_infra = deployment_stages.get("deploy_cdk_bridge_infra")
    if deploy_cdk_bridge_infra and (
        consensus_type
        in [
            constants.CONSENSUS_TYPE.rollup,
            constants.CONSENSUS_TYPE.cdk_validium,
        ]
    ):
        plan.print("Deploying zkevm-bridge infrastructure (legacy)")
        bridge_service_url = zkevm_bridge_service.run(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            rpc_url,
        )

        if deployment_stages.get("deploy_cdk_bridge_ui"):
            bridge_ui_url = zkevm_bridge_ui.run(plan, args, contract_setup_addresses)

            if deployment_stages.get("deploy_l1"):
                zkevm_bridge_proxy.run(
                    plan,
                    args,
                    args.get("l1_rpc_url"),
                    rpc_url,
                    bridge_service_url,
                    bridge_ui_url,
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
