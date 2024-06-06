input_parser = "./input_parser.star"
ethereum_package = "./ethereum.star"
deploy_zkevm_contracts_package = "./deploy_zkevm_contracts.star"
databases_package = "./databases.star"
cdk_central_environment_package = "./cdk_central_environment.star"
cdk_bridge_infra_package = "./cdk_bridge_infra.star"
zkevm_permissionless_node_package = "./zkevm_permissionless_node.star"
cdk_erigon_rpc_package = "./cdk_erigon_rpc.star"
observability_package = "./observability.star"
blockscout_package = "./blockscout.star"
workload_package = "./workload.star"
blutgang_package = "./cdk_blutgang.star"


def run(
    plan,
    deploy_l1=True,
    deploy_zkevm_contracts_on_l1=True,
    deploy_databases=True,
    deploy_cdk_bridge_infra=True,
    deploy_cdk_central_environment=True,
    deploy_zkevm_permissionless_node=False,
    deploy_cdk_erigon_rpc=False,
    deploy_observability=True,
    deploy_l2_blockscout=False,
    deploy_blutgang=False,
    apply_workload=False,
    args={},
):
    """Deploy a Polygon CDK Devnet with various configurable options.

    Args:
        deploy_l1 (bool): Deploy local l1.
        deploy_zkevm_contracts_on_l1(bool): Deploy zkevm contracts on L1 (and also fund accounts).
        deploy_databases(bool): Deploy zkevm node and cdk peripheral databases.
        deploy_cdk_central_environment(bool): Deploy cdk central/trusted environment.
        deploy_cdk_bridge_infra(bool): Deploy cdk/bridge infrastructure.
        deploy_zkevm_permissionless_node(bool): Deploy permissionless node.
        deploy_observability(bool): Deploys observability stack.
        deploy_l2_blockscout(bool): Deploys Blockscout stack.
        args(json): Configures other aspects of the environment.
    Returns:
        A full deployment of Polygon CDK.
    """

    args = import_module(input_parser).parse_args(args)

    plan.print("Deploying CDK environment...")

    # Deploy a local L1.
    if deploy_l1:
        plan.print("Deploying a local L1")
        import_module(ethereum_package).run(plan, args)
    else:
        plan.print("Skipping the deployment of a local L1")

    # Deploy zkevm contracts on L1.
    if deploy_zkevm_contracts_on_l1:
        plan.print("Deploying zkevm contracts on L1")
        import_module(deploy_zkevm_contracts_package).run(plan, args)
    else:
        plan.print("Skipping the deployment of zkevm contracts on L1")

    # Deploy helper service to retrieve rollup data from rollup manager contract.
    plan.print("Deploying helper service to retrieve rollup data")
    deploy_helper_service(plan, args)

    # Deploy zkevm node and cdk peripheral databases.
    if deploy_databases:
        plan.print("Deploying zkevm node and cdk peripheral databases")
        import_module(databases_package).run(plan, suffix=args["deployment_suffix"])
    else:
        plan.print("Skipping the deployment of zkevm node and cdk peripheral databases")

    # Get the genesis file.
    genesis_artifact = ""
    if deploy_cdk_central_environment:
        plan.print("Getting genesis file...")
        genesis_artifact = plan.store_service_files(
            name="genesis",
            service_name="contracts" + args["deployment_suffix"],
            src="/opt/zkevm/genesis.json",
        )

    # Deploy cdk central/trusted environment.
    if deploy_cdk_central_environment:
        plan.print("Deploying cdk central/trusted environment")
        central_environment_args = dict(args)
        central_environment_args["genesis_artifact"] = genesis_artifact
        import_module(cdk_central_environment_package).run(
            plan, central_environment_args
        )
    else:
        plan.print("Skipping the deployment of cdk central/trusted environment")

    # Deploy cdk/bridge infrastructure.
    if deploy_cdk_bridge_infra:
        plan.print("Deploying cdk/bridge infrastructure")
        import_module(cdk_bridge_infra_package).run(plan, args)
    else:
        plan.print("Skipping the deployment of cdk/bridge infrastructure")

    # Deploy permissionless node
    if deploy_zkevm_permissionless_node:
        plan.print("Deploying zkevm permissionless node")
        # Note that an additional suffix will be added to the permissionless services.
        permissionless_node_args = dict(args)
        permissionless_node_args["original_suffix"] = args["deployment_suffix"]
        permissionless_node_args["deployment_suffix"] = (
            "-pless" + args["deployment_suffix"]
        )
        permissionless_node_args["genesis_artifact"] = genesis_artifact
        import_module(databases_package).run_pless(
            plan, suffix=permissionless_node_args["original_suffix"]
        )
        import_module(zkevm_permissionless_node_package).run(
            plan, permissionless_node_args, genesis_artifact
        )
    else:
        plan.print("Skipping the deployment of zkevm permissionless node")

    # Deploy cdk-erigon rpc.
    if deploy_cdk_erigon_rpc:
        plan.print("Deploying cdk-erigon rpc")
        import_module(cdk_erigon_rpc_package).run(plan, args)
    else:
        plan.print("Skipping the deployment of cdk-erigon rpc")

    # Deploy observability stack
    if deploy_observability:
        plan.print("Deploying the observability stack")
        observability_args = dict(args)
        import_module(observability_package).run(plan, observability_args)
    else:
        plan.print("Skipping the deployment of the observability stack")

    # Deploy observability stack
    if deploy_l2_blockscout:
        plan.print("Deploying Blockscout stack")
        import_module(blockscout_package).run(plan, args)
    else:
        plan.print("Skipping the deployment of Blockscout stack")

    # Apply workload
    if apply_workload:
        plan.print("Applying workload")
        import_module(workload_package).run(plan, args)
    else:
        plan.print("Skipping workload application")

    # Deploy blutgang for caching
    if deploy_blutgang:
        plan.print("Deploying blutgang")
        blutgang_args = dict(args)
        import_module(blutgang_package).run(plan, blutgang_args)
    else:
        plan.print("Skipping the deployment of blutgang")


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
            image=args["toolbox_image"],
            files={"/opt/zkevm": get_rollup_info_artifact},
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
        ),
    )

    if "zkevm_rollup_manager_address" in args:
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
