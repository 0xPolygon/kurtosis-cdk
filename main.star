constants = import_module("./src/package_io/constants.star")
input_parser = import_module("./input_parser.star")
service_package = import_module("./lib/service.star")
op_succinct_package = import_module("./op_succinct.star")
deploy_sovereign_contracts_package = import_module("./deploy_sovereign_contracts.star")
aggkit_package = import_module("./aggkit.star")
ethereum_package = import_module("./ethereum.star")

# Main service packages.
additional_services = import_module("./src/additional_services/launcher.star")
agglayer_package = "./agglayer.star"
cdk_bridge_infra_package = "./cdk_bridge_infra.star"
cdk_central_environment_package = "./cdk_central_environment.star"
cdk_erigon_package = "./cdk_erigon.star"
databases_package = "./databases.star"
deploy_zkevm_contracts_package = "./deploy_zkevm_contracts.star"
anvil_package = "./anvil.star"
zkevm_pool_manager_package = "./zkevm_pool_manager.star"
deploy_l2_contracts_package = "./deploy_l2_contracts.star"
create_sovereign_predeployed_genesis_package = (
    "./create_sovereign_predeployed_genesis.star"
)
mitm_package = "./mitm.star"


def run(plan, args={}):
    # Parse args.
    (deployment_stages, args, op_stack_args) = input_parser.parse_args(plan, args)
    plan.print("Deploying the following components: " + str(deployment_stages))
    verbosity = args.get("verbosity", "")
    if verbosity == constants.LOG_LEVEL.debug or verbosity == constants.LOG_LEVEL.trace:
        plan.print("Deploying CDK stack with the following configuration: " + str(args))

    # Deploy a local L1.
    if deployment_stages.get("deploy_l1", False):
        plan.print(
            "Deploying a local L1 (based on {})".format(args.get("l1_engine", "geth"))
        )
        if args.get("l1_engine", "geth") == "anvil":
            import_module(anvil_package).run(plan, args)
        else:
            ethereum_package.run(plan, args)
    else:
        plan.print("Skipping the deployment of a local L1")
    # Extract the fetch-rollup-config binary before starting contracts-001 service.
    if deployment_stages.get("deploy_op_succinct", False):
        # Extract genesis to feed into evm-sketch-genesis
        # ethereum_package.extract_genesis_json(plan)
        # Temporarily run op-succinct-proposer service and fetch-rollup-config binary
        # The extract binary will be passed into the contracts-001 service
        op_succinct_package.extract_fetch_rollup_config(plan, args)

    # Deploy Contracts on L1.
    contract_setup_addresses = {}
    sovereign_contract_setup_addresses = {}
    if deployment_stages.get("deploy_zkevm_contracts_on_l1", False):
        plan.print("Deploying zkevm contracts on L1")
        import_module(deploy_zkevm_contracts_package).run(
            plan, args, deployment_stages, op_stack_args
        )

        if deployment_stages.get("deploy_optimism_rollup", False):
            # Deploy Sovereign contracts (maybe a better name is creating soverign rollup)
            # TODO rename this and understand what this does in the case where there are predeployed contracts
            # TODO Call the create rollup script
            plan.print("Creating new rollup type and creating rollup on L1")
            deploy_sovereign_contracts_package.run(
                plan, args, op_stack_args["predeployed_contracts"]
            )

            import_module(create_sovereign_predeployed_genesis_package).run(plan, args)

            # Deploy OP Stack infrastructure
            plan.print("Deploying an OP Stack rollup with args: " + str(op_stack_args))
            optimism_package = op_stack_args["source"]
            import_module(optimism_package).run(plan, op_stack_args)

            # Retrieve L1 OP contract addresses.
            op_deployer_configs_artifact = plan.get_files_artifact(
                name="op-deployer-configs",
            )

            # Fund OP Addresses on L1
            l1_op_contract_addresses = service_package.get_l1_op_contract_addresses(
                plan, args, op_deployer_configs_artifact
            )

            deploy_sovereign_contracts_package.fund_addresses(
                plan, args, l1_op_contract_addresses, args["l1_rpc_url"]
            )

            # Fund Kurtosis addresses on OP L2
            l2_kurtosis_addresses = service_package.get_kurtosis_addresses(args)

            deploy_sovereign_contracts_package.fund_addresses(
                plan, args, l2_kurtosis_addresses, args["op_el_rpc_url"]
            )

            if deployment_stages.get("deploy_op_succinct", False):
                # Extract genesis to feed into evm-sketch-genesis
                op_succinct_package.create_evm_sketch_genesis(plan, args)

                # Run deploy-op-succinct-contracts.sh script in the contracts-001 service
                plan.exec(
                    description="Deploying op-succinct contracts",
                    service_name="contracts" + args["deployment_suffix"],
                    recipe=ExecRecipe(
                        command=[
                            "/bin/bash",
                            "-c",
                            "cp /opt/scripts/deploy-op-succinct-contracts.sh /opt/op-succinct/ && chmod +x {0} && {0}".format(
                                "/opt/op-succinct/deploy-op-succinct-contracts.sh"
                            ),
                        ]
                    ),
                )
                plan.print("Extracting environment variables for op-succinct")
                op_succinct_env_vars = service_package.get_op_succinct_env_vars(
                    plan, args
                )
                args = args | op_succinct_env_vars
                l2oo_vars = service_package.get_op_succinct_l2oo_config(plan, args)
                args = args | l2oo_vars

            # TODO/FIXME this might break PP. We need to make sure that this process can work with PP and FEP. If it can work with PP, then we need to remove the dependency on l2oo (i think)
            plan.print("Initializing rollup")
            deploy_sovereign_contracts_package.init_rollup(
                plan, args, deployment_stages
            )
            # Extract Sovereign contract addresses
            sovereign_contract_setup_addresses = (
                service_package.get_sovereign_contract_setup_addresses(plan, args)
            )

        contract_setup_addresses = service_package.get_contract_setup_addresses(
            plan, args, deployment_stages
        )
    else:
        plan.print("Skipping the deployment of zkevm contracts on L1")

    # Deploy helper service to retrieve rollup data from rollup manager contract.
    if (
        "zkevm_rollup_manager_address" in args
        and "zkevm_rollup_manager_block_number" in args
        and "zkevm_global_exit_root_l2_address" in args
        and "polygon_data_committee_address" in args
    ):
        plan.print("Deploying helper service to retrieve rollup data")
        deploy_helper_service(plan, args)
        contract_setup_addresses = service_package.get_contract_setup_addresses(
            plan, args
        )
    else:
        plan.print("Skipping the deployment of helper service to retrieve rollup data")

    # Deploy databases.
    if deployment_stages.get("deploy_databases", False):
        plan.print("Deploying databases")
        import_module(databases_package).run(plan, args)
    else:
        plan.print("Skipping the deployment of databases")

    # Get the genesis file.
    genesis_artifact = ""
    if not deployment_stages.get("deploy_optimism_rollup", False):
        if deployment_stages.get("deploy_cdk_central_environment", False):
            plan.print("Getting genesis file")
            genesis_artifact = plan.store_service_files(
                name="genesis",
                service_name="contracts" + args["deployment_suffix"],
                src="/opt/zkevm/genesis.json",
            )

    # Deploy MITM
    if any(args["mitm_proxied_components"].values()):
        plan.print("Deploying MITM")
        import_module(mitm_package).run(plan, args)
    else:
        plan.print("Skipping the deployment of MITM")

    # Deploy the agglayer.
    if deployment_stages.get("deploy_agglayer", False):
        plan.print("Deploying the agglayer")
        import_module(agglayer_package).run(
            plan, deployment_stages, args, contract_setup_addresses
        )
    else:
        plan.print("Skipping the deployment of the agglayer")

    if not deployment_stages.get("deploy_optimism_rollup", False):
        # Deploy cdk central/trusted environment.
        if deployment_stages.get("deploy_cdk_central_environment", False):
            # Deploy cdk-erigon sequencer node.
            if args["sequencer_type"] == "erigon":
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
            else:
                plan.print("Skipping the deployment of cdk-erigon sequencer")

            # Deploy zkevm-pool-manager service.
            if deployment_stages.get("deploy_cdk_erigon_node", False):
                plan.print("Deploying zkevm-pool-manager service")
                import_module(zkevm_pool_manager_package).run_zkevm_pool_manager(
                    plan, args
                )
            else:
                plan.print("Skipping the deployment of zkevm-pool-manager service")

            # Deploy cdk-erigon node.
            if deployment_stages.get("deploy_cdk_erigon_node", False):
                plan.print("Deploying cdk-erigon node")
                import_module(cdk_erigon_package).run_rpc(
                    plan,
                    args
                    | {
                        "l1_rpc_url": args["mitm_rpc_url"].get(
                            "erigon-rpc", args["l1_rpc_url"]
                        )
                    },
                    contract_setup_addresses,
                )
            else:
                plan.print("Skipping the deployment of cdk-erigon node")

            plan.print("Deploying cdk central/trusted environment")
            args["genesis_artifact"] = genesis_artifact
            import_module(cdk_central_environment_package).run(
                plan, args, deployment_stages, contract_setup_addresses
            )

            # Deploy contracts on L2.
            plan.print("Deploying contracts on L2")
            deploy_l2_contracts = deployment_stages.get("deploy_l2_contracts", False)
            import_module(deploy_l2_contracts_package).run(
                plan, args, deploy_l2_contracts
            )
        else:
            plan.print("Skipping the deployment of cdk central/trusted environment")

        # Deploy cdk/bridge infrastructure.
        if deployment_stages.get("deploy_cdk_bridge_infra", False):
            plan.print("Deploying cdk/bridge infrastructure")
            import_module(cdk_bridge_infra_package).run(
                plan,
                args | {"use_local_l1": deployment_stages.get("deploy_l1", False)},
                contract_setup_addresses,
                deploy_bridge_ui=deployment_stages.get("deploy_cdk_bridge_ui", True),
                deploy_optimism_rollup=deployment_stages.get(
                    "deploy_optimism_rollup", False
                ),
            )
        else:
            plan.print("Skipping the deployment of cdk/bridge infrastructure")

    # Deploy OP Succinct.
    if deployment_stages.get("deploy_op_succinct", False):
        # Run op-succinct-proposer service
        plan.print("Running the op-succinct-proposer service")
        op_succinct_package.op_succinct_proposer_run(
            plan, args | contract_setup_addresses
        )
    else:
        plan.print("Skipping the deployment of OP Succinct")

    # Deploy AggKit infrastructure + Dedicated Bridge Service
    if deployment_stages.get("deploy_optimism_rollup", False):
        plan.print("Deploying AggKit infrastructure")
        aggkit_package.run(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            deployment_stages,
        )
    else:
        plan.print("Skipping the deployment of aggkit infrastructure")

    # Deploy additional services.
    deploy_optimism_rollup = deployment_stages.get("deploy_optimism_rollup", False)
    additional_services.launch(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        genesis_artifact,
        deploy_optimism_rollup,
    )


def deploy_helper_service(plan, args):
    # Create script artifact.
    get_rollup_info_template = read_file(src="./templates/get-rollup-info.sh")
    get_rollup_info_artifact = plan.render_templates(
        name="get-rollup-info-artifact",
        config={
            "get-rollup-info.sh": struct(
                template=get_rollup_info_template,
                data=args
                | {
                    "rpc_url": args["l1_rpc_url"],
                },
            )
        },
    )

    # Deploy helper service.
    helper_service_name = "helper" + args["deployment_suffix"]
    plan.add_service(
        name=helper_service_name,
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={"/opt/zkevm": get_rollup_info_artifact},
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
        ),
    )

    # Retrieve rollup data.
    plan.exec(
        description="Retrieving rollup data from the rollup manager contract",
        service_name=helper_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format(
                    "/opt/zkevm/get-rollup-info.sh",
                ),
            ]
        ),
    )
