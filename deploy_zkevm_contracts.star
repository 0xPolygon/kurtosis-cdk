data_availability_package = import_module("./lib/data_availability.star")


ARTIFACTS = [
    {
        "name": "deploy_parameters.json",
        "file": "./templates/contract-deploy/deploy_parameters.json",
    },
    {
        "name": "create_rollup_parameters.json",
        "file": "./templates/contract-deploy/create_rollup_parameters.json",
    },
    {
        "name": "run-contract-setup.sh",
        "file": "./templates/contract-deploy/run-contract-setup.sh",
    },
    {
        "name": "create-keystores.sh",
        "file": "./templates/contract-deploy/create-keystores.sh",
    },
    {
        "name": "update-ger.sh",
        "file": "./templates/contract-deploy/update-ger.sh",
    },
    {
        "name": "run-l2-contract-setup.sh",
        "file": "./templates/contract-deploy/run-l2-contract-setup.sh",
    },
    {
        "name": "run-sovereign-setup.sh",
        "file": "./templates/sovereign-rollup/run-sovereign-setup.sh",
    },
    {
        "name": "run-sovereign-setup-predeployed.sh",
        "file": "./templates/sovereign-rollup/run-sovereign-setup-predeployed.sh",
    },
    {
        "name": "create_new_rollup.json",
        "file": "./templates/sovereign-rollup/create_new_rollup.json",
    },
    {
        "name": "add_rollup_type.json",
        "file": "./templates/sovereign-rollup/add_rollup_type.json",
    },
    {
        "name": "sovereign-genesis.json",
        "file": "./templates/sovereign-rollup/genesis.json",
    },
    {
        "name": "create-genesis-sovereign-params.json",
        "file": "./templates/sovereign-rollup/create-genesis-sovereign-params.json",
    },
    {
        "name": "create-predeployed-sovereign-genesis.sh",
        "file": "./templates/sovereign-rollup/create-predeployed-sovereign-genesis.sh",
    },
    {
        "name": "op-original-genesis.json",
        "file": "./templates/sovereign-rollup/op-original-genesis.json",
    },
    {
        "name": "fund-addresses.sh",
        "file": "./templates/sovereign-rollup/fund-addresses.sh",
    },
    {
        "name": "run-initialize-rollup.sh",
        "file": "./templates/sovereign-rollup/run-initialize-rollup.sh",
    },
]


def run(plan, args, deployment_stages, op_stack_args):
    artifact_paths = list(ARTIFACTS)
    # If we are configured to use a previous deployment, we'll
    # dynamically add artifacts for the genesis and combined outputs.
    if args.get("use_previously_deployed_contracts"):
        artifact_paths.append(
            {
                "name": "genesis.json",
                "file": "./templates/contract-deploy/genesis.json",
            }
        )
        artifact_paths.append(
            {
                "name": "combined.json",
                "file": "./templates/contract-deploy/combined.json",
            }
        )
        artifact_paths.append(
            {
                "name": "dynamic-" + args["chain_name"] + "-conf.json",
                "file": "./templates/contract-deploy/dynamic-"
                + args["chain_name"]
                + "-conf.json",
            }
        )
        artifact_paths.append(
            {
                "name": "dynamic-" + args["chain_name"] + "-allocs.json",
                "file": "./templates/contract-deploy/dynamic-"
                + args["chain_name"]
                + "-allocs.json",
            }
        )

    artifacts = []
    for artifact_cfg in artifact_paths:
        template = read_file(src=artifact_cfg["file"])
        artifact = plan.render_templates(
            name=artifact_cfg["name"],
            config={
                artifact_cfg["name"]: struct(
                    template=template,
                    data=args
                    | {
                        "is_cdk_validium": data_availability_package.is_cdk_validium(
                            args
                        ),
                        "deploy_op_succinct": deployment_stages.get(
                            "deploy_op_succinct", False
                        ),
                        "zkevm_rollup_consensus": data_availability_package.get_consensus_contract(
                            args
                        ),
                        "deploy_optimism_rollup": deployment_stages.get(
                            "deploy_optimism_rollup", False
                        ),
                        "op_stack_seconds_per_slot": op_stack_args["optimism_package"][
                            "chains"
                        ][0]["network_params"]["seconds_per_slot"],
                    },
                )
            },
        )
        artifacts.append(artifact)

    # Create helper service to deploy contracts
    contracts_service_name = "contracts" + args["deployment_suffix"]
    plan.add_service(
        name=contracts_service_name,
        config=ServiceConfig(
            image=args["zkevm_contracts_image"],
            files={
                "/opt/zkevm": Directory(persistent_key="zkevm-artifacts"),
                "/opt/contract-deploy/": Directory(artifact_names=artifacts),
            },
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )

    # Deploy contracts.
    plan.exec(
        description="Deploying zkevm contracts on L1",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format(
                    "/opt/contract-deploy/run-contract-setup.sh"
                ),
            ]
        ),
    )

    # Create keystores.
    plan.exec(
        description="Creating keystores for zkevm-node/cdk-validium components",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format(
                    "/opt/contract-deploy/create-keystores.sh"
                ),
            ]
        ),
    )

    # Store CDK configs.
    plan.store_service_files(
        name="cdk-erigon-chain-config",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/dynamic-" + args["chain_name"] + "-conf.json",
    )

    plan.store_service_files(
        name="cdk-erigon-chain-allocs",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/dynamic-" + args["chain_name"] + "-allocs.json",
    )
    plan.store_service_files(
        name="cdk-erigon-chain-first-batch",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/first-batch-config.json",
    )

    # Force update GER.
    plan.exec(
        description="Updating the GER so the L1 Info Tree Index is greater than 0",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format("/opt/contract-deploy/update-ger.sh"),
            ]
        ),
    )
