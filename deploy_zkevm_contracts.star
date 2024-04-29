def run(plan, args):
    # Create deploy parameters
    deploy_parameters_template = read_file(
        src="./templates/contract-deploy/deploy_parameters.json"
    )
    deploy_parameters_artifact = plan.render_templates(
        name="deploy-parameters-artifact",
        config={
            "deploy_parameters.json": struct(
                template=deploy_parameters_template,
                data=args,
            )
        },
    )

    # Create rollup paramaters
    create_rollup_parameters_template = read_file(
        src="./templates/contract-deploy/create_rollup_parameters.json"
    )
    create_rollup_parameters_artifact = plan.render_templates(
        name="create-rollup-parameters-artifact",
        config={
            "create_rollup_parameters.json": struct(
                template=create_rollup_parameters_template,
                data=args,
            )
        },
    )

    # Create contract deployment script
    contract_deployment_script_template = read_file(
        src="./templates/contract-deploy/run-contract-setup.sh"
    )
    contract_deployment_script_artifact = plan.render_templates(
        name="contract-deployment-script-artifact",
        config={
            "run-contract-setup.sh": struct(
                template=contract_deployment_script_template,
                data=args,
            ),
        },
    )

    # Create keystores script
    create_keystores_script_template = read_file(
        src="./templates/contract-deploy/create-keystores.sh"
    )
    create_keystores_script_artifact = plan.render_templates(
        name="create-keystores-script-artifact",
        config={
            "create-keystores.sh": struct(
                template=create_keystores_script_template,
                data=args,
            ),
        },
    )

    # Create helper service to deploy contracts
    contracts_service_name = "contracts" + args["deployment_suffix"]
    zkevm_contracts_image = "{}:fork{}".format(
        args["zkevm_contracts_image"], args["zkevm_rollup_fork_id"]
    )
    plan.add_service(
        name=contracts_service_name,
        config=ServiceConfig(
            image=zkevm_contracts_image,
            files={
                "/opt/zkevm": Directory(persistent_key="zkevm-artifacts"),
                "/opt/contract-deploy/": Directory(
                    artifact_names=[
                        deploy_parameters_artifact,
                        create_rollup_parameters_artifact,
                        contract_deployment_script_artifact,
                        create_keystores_script_artifact,
                    ]
                ),
            },
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )

    # TODO: Check if the contracts were already initialized.. I'm leaving this here for now, but it's not useful!!
    contract_init_stat = plan.exec(
        description="Checking if contracts are already initialized",
        service_name=contracts_service_name,
        acceptable_codes=[0, 1],
        recipe=ExecRecipe(command=["stat", "/opt/zkevm/.init-complete.lock"]),
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
