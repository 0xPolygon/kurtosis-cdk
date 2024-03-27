deploy_l1_package = import_module("./deploy_l1.star")
configure_l1_package = import_module("./configure_l1.star")
cdk_central_environment_package = import_module("./cdk_central_environment.star")
cdk_bridge_package = import_module("./cdk_bridge.star")
zkevm_permissionless_node_package = import_module("./zkevm_permissionless_node.star")


DEPLOYMENT_STAGE = struct(
    deploy_l1=1,
    configure_l1=2,
    deploy_central_environment=3,
    deploy_cdk_bridge_infra=4,
    deploy_permissionless_node=5,
)


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

    args["is_cdk"] = False
    if args["zkevm_rollup_consensus"] == "PolygonValidiumEtrog":
        args["is_cdk"] = True

    ## STAGE 1: Deploy L1
    # For now we'll stick with most of the defaults
    if DEPLOYMENT_STAGE.deploy_l1 in args["stages"]:
        plan.print("Executing stage " + str(DEPLOYMENT_STAGE.deploy_l1))
        deploy_l1_package.run(plan, args)
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.deploy_l1))

    ## STAGE 2: Configure L1
    # Fund accounts, deploy cdk contracts and create config files.
    if DEPLOYMENT_STAGE.configure_l1 in args["stages"]:
        plan.print("Executing stage " + str(DEPLOYMENT_STAGE.configure_l1))
        configure_l1_package.run(plan, args)
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.configure_l1))

    # Get the genesis file.
    genesis_artifact = ""
    if (
        DEPLOYMENT_STAGE.deploy_central_environment in args["stages"]
        or DEPLOYMENT_STAGE.deploy_permissionless_node in args["stages"]
    ):
        genesis_artifact = plan.store_service_files(
            name="genesis",
            service_name="contracts" + args["deployment_suffix"],
            src="/opt/zkevm/genesis.json",
        )

    ## STAGE 3: Deploy trusted / central environment
    if DEPLOYMENT_STAGE.deploy_central_environment in args["stages"]:
        cdk_central_environment_args = dict(args)
        cdk_central_environment_args["genesis_artifact"] = genesis_artifact
        plan.print(
            "Executing stage " + str(DEPLOYMENT_STAGE.deploy_central_environment)
        )
        cdk_central_environment_package.run(plan, cdk_central_environment_args)
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.deploy_central_environment))

    ## STAGE 4: Deploy CDK/Bridge infra
    if DEPLOYMENT_STAGE.deploy_cdk_bridge_infra in args["stages"]:
        plan.print("Executing stage " + str(DEPLOYMENT_STAGE.deploy_cdk_bridge_infra))
        cdk_bridge_package.run(plan, args)
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.deploy_cdk_bridge_infra))

    ## STAGE 5: Deploy permissionless node
    if DEPLOYMENT_STAGE.deploy_permissionless_node in args["stages"]:
        plan.print(
            "Executing stage " + str(DEPLOYMENT_STAGE.deploy_permissionless_node)
        )

        # Note that an additional suffix will be added to the permissionless services.
        permissionless_args = dict(args)  # Create a shallow copy of args.
        permissionless_args["deployment_suffix"] = "-pless" + args["deployment_suffix"]
        permissionless_args["genesis_artifact"] = genesis_artifact
        zkevm_permissionless_node_package.run(plan, permissionless_args)
    else:
        plan.print("Skipping stage " + str(DEPLOYMENT_STAGE.deploy_permissionless_node))
