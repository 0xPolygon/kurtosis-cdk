constants = import_module("./src/package_io/constants.star")
input_parser = import_module("./src/package_io/input_parser.star")
contracts_util = import_module("./src/contracts/util.star")
op_succinct_package = import_module("./src/chain/op-geth/op_succinct_proposer.star")

# Main service packages.
additional_services_launcher = import_module("./src/additional_services/launcher.star")
agglayer_package = "./src/agglayer.star"
l1_launcher = import_module("./src/l1/launcher.star")
chain_launcher = import_module("./src/chain/launcher.star")
databases_package = "./src/chain/shared/databases.star"
agglayer_contracts_package = "./src/contracts/agglayer.star"
sovereign_contracts_package = import_module("./src/contracts/sovereign.star")
mitm_package = "./src/mitm.star"


def run(plan, args={}):
    # Parse args.
    (deployment_stages, args, op_stack_args) = input_parser.parse_args(plan, args)
    plan.print("Deploying the following components: " + str(deployment_stages))
    plan.print("Deploying CDK stack with the following configuration: " + str(args))
    sequencer_type = args.get("sequencer_type")
    consensus_type = args.get("consensus_contract_type")

    # Deploy a local L1.
    if deployment_stages.get("deploy_l1", False):
        plan.print(
            "Deploying a local L1 (based on {})".format(args.get("l1_engine", "geth"))
        )
        l1_launcher.launch(plan, args)
    else:
        plan.print("Skipping the deployment of a local L1")

    # Retrieve L1 genesis and rename it to <l1_chain_id>.json for op-succinct
    # TODO: Fix the logic when using anvil and op-succinct
    if deployment_stages.get("deploy_op_succinct", False):
        l1_genesis_artifact = plan.get_files_artifact(name="el_cl_genesis_data")
        new_genesis_name = "{}.json".format(args.get("l1_chain_id"))
        result = plan.run_sh(
            name="rename-l1-genesis",
            description="Rename L1 genesis",
            files={"/tmp": l1_genesis_artifact},
            run="mv /tmp/genesis.json /tmp/{}".format(new_genesis_name),
            store=[
                StoreSpec(
                    src="/tmp/{}".format(new_genesis_name),
                    name="el_cl_genesis_data_for_op_succinct",
                )
            ],
        )
        artifact_count = len(result.files_artifacts)
        if artifact_count != 1:
            fail(
                "The service should have generated 1 artifact, got {}.".format(
                    artifact_count
                )
            )

    # Extract the fetch-l2oo-config binary before starting contracts-001 service.
    if deployment_stages.get("deploy_op_succinct", False):
        # Extract genesis to feed into evm-sketch-genesis
        # ethereum_package.extract_genesis_json(plan)
        # Temporarily run op-succinct-proposer service and fetch-l2oo-config binary
        # The extract binary will be passed into the contracts-001 service
        op_succinct_package.extract_fetch_l2oo_config(plan, args)

    # Deploy Contracts on L1.
    contract_setup_addresses = {}
    sovereign_contract_setup_addresses = {}
    if deployment_stages.get("deploy_agglayer_contracts_on_l1", False):
        plan.print("Deploying agglayer contracts on L1")
        import_module(agglayer_contracts_package).run(
            plan, args, deployment_stages, op_stack_args
        )

        if sequencer_type == constants.SEQUENCER_TYPE.op_geth:
            # Deploy Sovereign contracts (maybe a better name is creating sovereign rollup)
            # TODO rename this and understand what this does in the case where there are predeployed contracts
            # TODO Call the create rollup script
            plan.print("Creating new rollup type and creating rollup on L1")
            sovereign_contracts_package.run(
                plan, args, op_stack_args["predeployed_contracts"]
            )

            # This is required to push an artifact for predeployed_allocs that will be used from optimism-package
            import_module(
                agglayer_contracts_package
            ).create_sovereign_predeployed_genesis(plan, args)

            # Deploy OP Stack infrastructure
            plan.print("Deploying an OP Stack rollup with args: " + str(op_stack_args))
            optimism_package = op_stack_args["source"]
            import_module(optimism_package).run(plan, op_stack_args)

            # Retrieve L1 OP contract addresses.
            op_deployer_configs_artifact = plan.get_files_artifact(
                name="op-deployer-configs",
            )

            # Fund OP Addresses on L1
            l1_op_contract_addresses = contracts_util.get_l1_op_contract_addresses(
                plan, args, op_deployer_configs_artifact
            )

            sovereign_contracts_package.fund_addresses(
                plan, args, l1_op_contract_addresses, args["l1_rpc_url"]
            )

            # Fund Kurtosis addresses on OP L2
            sovereign_contracts_package.fund_addresses(
                plan,
                args,
                contracts_util.get_l2_addresses_to_fund(args),
                args["op_el_rpc_url"],
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
                            "cp {1}/deploy-op-succinct-contracts.sh /opt/op-succinct/ && chmod +x {0} && {0}".format(
                                "/opt/op-succinct/deploy-op-succinct-contracts.sh",
                                constants.SCRIPTS_DIR,
                            ),
                        ]
                    ),
                )
                plan.print("Extracting environment variables for op-succinct")
                op_succinct_env_vars = contracts_util.get_op_succinct_env_vars(
                    plan, args
                )
                args = args | op_succinct_env_vars
                l2oo_vars = contracts_util.get_op_succinct_l2oo_config(plan, args)
                args = args | l2oo_vars

            # TODO/FIXME this might break PP. We need to make sure that this process can work with PP and FEP. If it can work with PP, then we need to remove the dependency on l2oo (i think)
            plan.print("Initializing rollup")
            sovereign_contracts_package.init_rollup(plan, args, deployment_stages)
            # Extract Sovereign contract addresses
            sovereign_contract_setup_addresses = (
                contracts_util.get_sovereign_contract_setup_addresses(plan, args)
            )

        contract_setup_addresses = contracts_util.get_contract_setup_addresses(
            plan, args, deployment_stages
        )
    else:
        plan.print("Skipping the deployment of agglayer contracts on L1")

    # Deploy helper service to retrieve rollup data from rollup manager contract.
    if (
        "zkevm_rollup_manager_address" in args
        and "zkevm_rollup_manager_block_number" in args
        and "zkevm_global_exit_root_l2_address" in args
        and "polygon_data_committee_address" in args
    ):
        plan.print("Deploying helper service to retrieve rollup data")
        deploy_helper_service(plan, args)
        contract_setup_addresses = contracts_util.get_contract_setup_addresses(
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
    if sequencer_type == constants.SEQUENCER_TYPE.cdk_erigon:
        if deployment_stages.get("deploy_cdk_central_environment", False):
            plan.print("Getting genesis file")
            genesis_artifact = plan.store_service_files(
                name="genesis",
                service_name="contracts" + args["deployment_suffix"],
                src=constants.OUTPUT_DIR + "/genesis.json",
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

    # Deploy cdk central/trusted environment.
    if deployment_stages.get("deploy_cdk_central_environment", False):
        chain_launcher.launch(
            plan,
            args,
            contract_setup_addresses,
            sovereign_contract_setup_addresses,
            deployment_stages,
            genesis_artifact,
        )

    # Deploy contracts on L2.
    if deployment_stages.get("deploy_l2_contracts", False):
        plan.print("Deploying contracts on L2")
        import_module(agglayer_contracts_package).deploy_l2_contracts(plan, args)

    # Deploy additional services.
    additional_services_launcher.launch(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        genesis_artifact,
        deployment_stages,
        sequencer_type,
    )


def deploy_helper_service(plan, args):
    # Create script artifact.
    get_rollup_info_template = read_file(
        src="./static_files/scripts/get-rollup-info.sh"
    )
    get_rollup_info_artifact = plan.render_templates(
        name="get-rollup-info-artifact",
        config={
            "get-rollup-info.sh": struct(
                template=get_rollup_info_template,
                data=args
                | {
                    "rpc_url": args["l1_rpc_url"],
                    "output_dir": constants.OUTPUT_DIR,
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
            files={constants.OUTPUT_DIR: get_rollup_info_artifact},
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
                    "{}/get-rollup-info.sh".format(constants.OUTPUT_DIR),
                ),
            ]
        ),
    )
