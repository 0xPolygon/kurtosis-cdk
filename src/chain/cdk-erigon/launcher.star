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


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
    genesis_artifact,
):
    # cdk-erigon sequencer and its components
    if args.get("erigon_strict_mode"):
        zkevm_prover.run_stateless_executor(plan, args)

    # cdk-erigon sequencer
    result = cdk_erigon.run_sequencer(
        plan,
        args
        | {
            "l1_rpc_url": args["mitm_rpc_url"].get(
                "erigon-sequencer", args["l1_rpc_url"]
            )
        },
        contract_setup_addresses,
    )
    sequencer_url = result.ports[ports_package.HTTP_RPC_PORT_ID].url
    datastreamer_url = result.ports[cdk_erigon.DATA_STREAMER_PORT_ID].url.removeprefix(
        "datastream://"
    )

    # zkevm-pool-manager
    result = zkevm_pool_manager.run(plan, args, sequencer_url)
    pool_manager_url = result.ports[zkevm_pool_manager.SERVER_PORT_ID].url

    # cdk-erigon rpc
    result = cdk_erigon.run_rpc(
        plan,
        args
        | {"l1_rpc_url": args["mitm_rpc_url"].get("erigon-rpc", args["l1_rpc_url"])},
        contract_setup_addresses,
        struct(
            sequencer_url=sequencer_url,
            datastreamer_url=datastreamer_url,
            pool_manager_url=pool_manager_url,
        ),
    )
    rpc_url = result.ports[ports_package.HTTP_RPC_PORT_ID].url

    # TODO: understand if genesis_artifact is needed here or can be removed
    args["genesis_artifact"] = genesis_artifact

    # cdk-data-availability (validium only)
    consensus_type = args.get("consensus_contract_type")
    if consensus_type == constants.CONSENSUS_TYPE.cdk_validium:
        cdk_data_availability.run(plan, args, contract_setup_addresses)

    # cdk-node and zkevm-prover (rollup and validium)
    if consensus_type in [
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
    ]:
        cdk_node.run(plan, args, contract_setup_addresses, genesis_artifact)

        # zkevm-prover
        if not args.get("zkevm_use_real_verifier") and not args.get("enable_normalcy"):
            zkevm_prover.run_prover(plan, args)

    # aggkit
    if deployment_stages.get("deploy_aggkit_node"):
        plan.print("Deploying aggkit")
        aggkit_package.run_aggkit_cdk_node(
            plan,
            args,
            contract_setup_addresses,
        )

    # fund cdk-erigon account on L2
    agglayer_contracts_package.l2_legacy_fund_accounts(plan, args)

    # Deploy aggkit infrastructure + dedicated bridge service
    aggkit_bridge_url = None
    if consensus_type in [
        constants.CONSENSUS_TYPE.pessimistic,
        constants.CONSENSUS_TYPE.ecdsa_multisig,
    ]:
        plan.print("Deploying aggkit infrastructure")
        aggkit_bridge_url = aggkit_package.run(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            deployment_stages,
        )

    return struct(
        rpc_url=rpc_url,
        aggkit_bridge_url=aggkit_bridge_url if aggkit_bridge_url else None,
    )
