input_parser = "./input_parser.star"
ethereum_package = "./ethereum.star"
deploy_zkevm_contracts_package = "./deploy_zkevm_contracts.star"
databases_package = "./databases.star"
cdk_central_environment_package = "./cdk_central_environment.star"
cdk_bridge_infra_package = "./cdk_bridge_infra.star"
zkevm_permissionless_node_package = "./zkevm_permissionless_node.star"
observability_package = "./observability.star"
blockscout_package = "./blockscout.star"
workload_package = "./workload.star"
blutgang_package = "./cdk_blutgang.star"
cdk_erigon_package = import_module("./cdk_erigon.star")
zkevm_pool_manager_package = import_module("./zkevm_pool_manager.star")


def run(
    plan,
    deploy_l1=True,
    deploy_zkevm_contracts_on_l1=True,
    deploy_databases=True,
    deploy_cdk_bridge_infra=True,
    deploy_cdk_central_environment=True,
    deploy_cdk_erigon_node=True,
    deploy_observability=True,
    deploy_l2_blockscout=False,
    apply_workload=False,
    args={},
):
    args = import_module(input_parser).parse_args(args)

    plan.print("Deploying CDK environment...")

    if deploy_cdk_erigon_node:
        args["l2_rpc_name"] = "cdk-erigon-node"
    else:
        args["l2_rpc_name"] = "zkevm-node-rpc"

    if args["sequencer_type"] == "erigon":
        args["sequencer_name"] = "cdk-erigon-sequencer"
    else:
        args["sequencer_name"] = "zkevm-node-sequencer"

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
    if (
        "zkevm_rollup_manager_address" in args
        and "zkevm_rollup_manager_block_number" in args
        and "zkevm_global_exit_root_l2_address" in args
        and "polygon_data_committee_address" in args
    ):
        plan.print("Deploying helper service to retrieve rollup data")
        deploy_helper_service(plan, args)
    else:
        plan.print("Skipping the deployment of helper service to retrieve rollup data")

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
        # Deploy cdk-erigon sequencer node.
        # TODO this is a little weird if the erigon sequencer is deployed before the exector?
        if args["sequencer_type"] == "erigon":
            plan.print("Deploying cdk-erigon sequencer")
            cdk_erigon_package.run_sequencer(plan, args)
        else:
            plan.print("Skipping the deployment of cdk-erigon sequencer")

        # Deploy cdk-erigon node.
        if deploy_cdk_erigon_node:
            plan.print("Deploying cdk-erigon node")
            cdk_erigon_package.run_rpc(plan, args)
        else:
            plan.print("Skipping the deployment of cdk-erigon node")

        # Deploy zkevm-pool-manager service.
        if deploy_cdk_erigon_node:
            plan.print("Deploying zkevm-pool-manager service")
            zkevm_pool_manager_package.run_zkevm_pool_manager(plan, args)
        else:
            plan.print("Skipping the deployment of zkevm-pool-manager service")

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
        args["deploy_l1"] = deploy_l1
        import_module(cdk_bridge_infra_package).run(plan, args)
    else:
        plan.print("Skipping the deployment of cdk/bridge infrastructure")

    # Parse additional services.
    if "zkevm-pless-node" in args.additional_services:
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
    elif "blutgang" in args.additional_services:
        plan.print("Deploying blutgang")
        blutgang_args = dict(args)
        import_module(blutgang_package).run(plan, blutgang_args)

    # Deploy observability stack.
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
