deploy_l1_package = import_module("./deploy_l1.star")
deploy_zkevm_contracts_package = import_module("./deploy_zkevm_contracts.star")
cdk_central_environment_package = import_module("./cdk_central_environment.star")
cdk_bridge_infra_package = import_module("./cdk_bridge_infra.star")
zkevm_permissionless_node_package = import_module("./zkevm_permissionless_node.star")


def run(plan, args):
    plan.print("Deploying CDK environment for stages: " + str(args["stages"]))

    # Determine system architecture
    cpu_arch_result = plan.run_sh(
        run="uname -m | tr -d '\n'", description="Determining CPU system architecture"
    )
    cpu_arch = cpu_arch_result.output
    plan.print("Running on {} architecture".format(cpu_arch))
    if not "cpu_arch" in args:
        args["cpu_arch"] = cpu_arch

    args["is_cdk_validium"] = False
    if args["zkevm_rollup_consensus"] == "PolygonValidiumEtrog":
        args["is_cdk_validium"] = True

    # Deploy a local L1.
    if args["deploy_l1"]:
        plan.print("Deploying a local L1")
        deploy_l1_package.run(plan, args)
    else:
        plan.print("Skipping the deployment of a local L1")

    # Deploy zkevm contracts on L1
    if args["deploy_zkevm_contracts_on_l1"]:
        plan.print("Deploying zkevm contracts on L1")
        deploy_zkevm_contracts_package.run(plan, args)
    else:
        plan.print("Skipping the deployment of zkevm contracts on L1")

    # Get the genesis file.
    genesis_artifact = ""
    if args["deploy_central_environment"] or args["deploy_zkevm_permissionless_node"]:
        genesis_artifact = plan.store_service_files(
            name="genesis",
            service_name="contracts" + args["deployment_suffix"],
            src="/opt/zkevm/genesis.json",
        )

    # Deploy cdk central/trusted environment.
    if args["deploy_cdk_central_environment"]:
        plan.print("Deploying cdk central/trusted environment")
        central_environment_args = dict(args)
        central_environment_args["genesis_artifact"] = genesis_artifact
        central_environment_args.run(plan, central_environment_args)
    else:
        plan.print("Skipping the deployment of cdk central/trusted environment")

    # Deploy cdk/bridge infrastructure.
    if args["deploy_cdk_bridge_infra"]:
        plan.print("Deploying cdk/bridge infrastructure")
        cdk_bridge_infra_package.run(plan, args)
    else:
        plan.print("Skipping the deployment of cdk/bridge infrastructure")

    # Deploy permissionless node
    if args["deploy_zkevm_permissionless_node"]:
        plan.print("Deploying zkevm permissionless node")
        # Note that an additional suffix will be added to the permissionless services.
        permissionless_node_args = dict(args)  # Create a shallow copy of args.
        permissionless_node_args["deployment_suffix"] = (
            "-pless" + args["deployment_suffix"]
        )
        permissionless_node_args["genesis_artifact"] = genesis_artifact
        zkevm_permissionless_node_package.run(plan, permissionless_node_args)
    else:
        plan.print("Skipping the deployment of zkevm permissionless node")
