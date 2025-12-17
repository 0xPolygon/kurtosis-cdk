aggkit_package = import_module("../../../aggkit.star")
agglayer_contracts_package = import_module("../../contracts/agglayer.star")
cdk_bridge_infra_package = import_module("../../../cdk_bridge_infra.star")
cdk_erigon = import_module("./cdk_erigon.star")
cdk_node_package = import_module("../../../lib/cdk_node.star")
constants = import_module("../../package_io/constants.star")
databases = import_module("../shared/databases.star")
cdk_data_availability = import_module("./cdk_data_availability.star")
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

    zkevm_pool_manager.run(plan, args)
    cdk_erigon.run_sequencer(
        plan,
        args
        | {
            "l1_rpc_url": args["mitm_rpc_url"].get(
                "erigon-sequencer", args["l1_rpc_url"]
            )
        },
        contract_setup_addresses,
    )

    # cdk-erigon rpc
    cdk_erigon.run_rpc(
        plan,
        args
        | {"l1_rpc_url": args["mitm_rpc_url"].get("erigon-rpc", args["l1_rpc_url"])},
        contract_setup_addresses,
    )

    # TODO: understand if genesis_artifact is needed here or can be removed
    args["genesis_artifact"] = genesis_artifact

    # cdk-data-availability
    consensus_type = args.get("consensus_contract_type")
    if consensus_type == constants.CONSENSUS_TYPE.cdk_validium:
        cdk_data_availability.run(plan, args, contract_setup_addresses)

    # rollup and validium specific
    if consensus_type in [
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
    ]:
        # cdk-node
        db_configs = databases.get_db_configs(
            args["deployment_suffix"], args["sequencer_type"]
        )
        keystore_artifacts = get_keystores_artifacts(plan, args)
        agglayer_endpoint = get_agglayer_endpoint(plan, args)
        node_config_template = read_file(
            src="../../../templates/trusted-node/cdk-node-config.toml"
        )
        node_config_artifact = plan.render_templates(
            name="cdk-node-config-artifact",
            config={
                "cdk-node-config.toml": struct(
                    template=node_config_template,
                    data=args
                    | {
                        "is_validium_mode": is_validium_mode,
                        "l1_rpc_url": args["mitm_rpc_url"].get(
                            "cdk-node", args["l1_rpc_url"]
                        ),
                        "agglayer_endpoint": agglayer_endpoint,
                    }
                    | db_configs
                    | contract_setup_addresses,
                )
            },
        )
        cdk_node_configs = cdk_node_package.create_cdk_node_service_config(
            args, node_config_artifact, genesis_artifact, keystore_artifacts
        )
        plan.add_services(
            configs=cdk_node_configs,
            description="Starting the cdk node components",
        )

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

    # Deploy cdk/bridge infrastructure only if using CDK Node instead of Aggkit. This can be inferred by the consensus_contract_type.
    deploy_cdk_bridge_infra = deployment_stages.get("deploy_cdk_bridge_infra")
    if deploy_cdk_bridge_infra and (
        consensus_type
        in [
            constants.CONSENSUS_TYPE.rollup,
            constants.CONSENSUS_TYPE.cdk_validium,
        ]
    ):
        plan.print("Deploying cdk/bridge infrastructure")
        cdk_bridge_infra_package.run(
            plan,
            args | {"use_local_l1": deployment_stages.get("deploy_l1")},
            contract_setup_addresses,
            deploy_bridge_ui=deployment_stages.get("deploy_cdk_bridge_ui"),
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


def get_keystores_artifacts(plan, args):
    sequencer_keystore_artifact = plan.store_service_files(
        name="sequencer-keystore",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/sequencer.keystore",
    )
    aggregator_keystore_artifact = plan.get_files_artifact(
        name="aggregator-keystore",
        # service_name="contracts" + args["deployment_suffix"],
        # src=constants.KEYSTORES_DIR+"/aggregator.keystore",
    )
    claim_sponsor_keystore_artifact = plan.store_service_files(
        name="claimsponsor-keystore-cdk",
        service_name="contracts" + args["deployment_suffix"],
        src=constants.KEYSTORES_DIR + "/claimsponsor.keystore",
    )
    return struct(
        sequencer=sequencer_keystore_artifact,
        aggregator=aggregator_keystore_artifact,
        claim_sponsor=claim_sponsor_keystore_artifact,
    )


# Function to allow cdk-node-config to pick whether to use agglayer_readrpc_port or agglayer_grpc_port depending on whether cdk-node or aggkit-node is being deployed.
# On aggkit/cdk-node point of view, only the agglayer_image version is important. Both services can work with both grpc/readrpc and this depends on the agglayer version.
# On Kurtosis point of view, we are checking whether the cdk-node or the aggkit node is being used to filter the grpc/readrpc.
def get_agglayer_endpoint(plan, args):
    if (
        "0.3" in args["agglayer_image"]
        and args.get("binary_name") == cdk_node_package.AGGKIT_BINARY_NAME
    ):
        return "grpc"
    elif args["sequencer_type"] == constants.SEQUENCER_TYPE.op_geth:
        return "grpc"
    else:
        return "readrpc"
