def run(plan, args):
    # Create deploy parameters
    deploy_parameters_template = read_file(src="./templates/deploy_parameters.json")
    deploy_parameters_artifact = plan.render_templates(
        name="deploy-parameters-artifact",
        config={
            "deploy_parameters.json": struct(
                template=deploy_parameters_template, data=args
            )
        },
    )

    # Create rollup paramaters
    create_rollup_parameters_template = read_file(
        src="./templates/create_rollup_parameters.json"
    )
    create_rollup_parameters_artifact = plan.render_templates(
        name="create-rollup-parameters-artifact",
        config={
            "create_rollup_parameters.json": struct(
                template=create_rollup_parameters_template, data=args
            )
        },
    )

    # Create contract deployment script
    contract_deployment_script_template = read_file(
        src="./templates/run-contract-setup.sh"
    )
    contract_deployment_script_artifact = plan.render_templates(
        name="contract-deployment-script-artifact",
        config={
            "run-contract-setup.sh": struct(
                template=contract_deployment_script_template, data=args
            )
        },
    )

    # Create helper service to deploy contracts
    zkevm_contracts_image = "{}:fork{}".format(
        args["zkevm_contracts_image"], args["zkevm_rollup_fork_id"]
    )
    plan.add_service(
        name="contracts" + args["deployment_suffix"],
        config=ServiceConfig(
            image=zkevm_contracts_image,
            files={
                "/opt/zkevm": Directory(persistent_key="zkevm-artifacts"),
                "/opt/contract-deploy/": Directory(
                    artifact_names=[
                        deploy_parameters_artifact,
                        create_rollup_parameters_artifact,
                        contract_deployment_script_artifact,
                    ]
                ),
            },
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )

    # TODO: Check if the contracts were already initialized.. I'm leaving this here for now, but it's not useful!!
    contract_init_stat = plan.exec(
        service_name="contracts" + args["deployment_suffix"],
        acceptable_codes=[0, 1],
        recipe=ExecRecipe(command=["stat", "/opt/zkevm/.init-complete.lock"]),
    )

    # Deploy contracts
    plan.exec(
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=["chmod", "a+x", "/opt/contract-deploy/run-contract-setup.sh"]
        ),
    )
    plan.print("Running zkEVM contract deployment. This might take some time...")
    plan.exec(
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(command=["/opt/contract-deploy/run-contract-setup.sh"]),
    )
