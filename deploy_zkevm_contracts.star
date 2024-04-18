def run(
    plan, 
    l1_rpc_url,
    l1_preallocated_mnemonic,
    zkevm_rollup_fork_id,
    zkevm_rollup_chain_id,
    zkevm_rollup_consensus,
    zkevm_l2_admin_address,
    zkevm_l2_admin_private_key,
    zkevm_l2_sequencer_address,
    zkevm_l2_sequencer_private_key,
    zkevm_l2_aggregator_address,
    zkevm_l2_aggregator_private_key,
    zkevm_l2_agglayer_address,
    zkevm_l2_agglayer_private_key,
    zkevm_l2_claimtxmanager_address,
    zkevm_l2_claimtxmanager_private_key,
    zkevm_l2_dac_address,
    zkevm_l2_dac_private_key,
    zkevm_dac_port,
    zkevm_rpc_http_port,
    deployment_suffix,
    ):
    # Create deploy parameters
    deploy_parameters_template = read_file(
        src="./templates/contract-deploy/deploy_parameters.json"
    )
    deploy_parameters_artifact = plan.render_templates(
        name="deploy-parameters-artifact",
        config={
            "deploy_parameters.json": struct(
                template=deploy_parameters_template, data= {
                    "zkevm_l2_admin_address": zkevm_l2_admin_address,
                    "zkevm_l2_admin_private_key": zkevm_l2_admin_private_key,
                    "zkevm_l2_sequencer_address": zkevm_l2_sequencer_address,
                    "zkevm_l2_aggregator_address": zkevm_l2_aggregator_address,
                    "zkevm_rollup_fork_id": zkevm_rollup_fork_id,
                    "zkevm_rpc_http_port": zkevm_rpc_http_port,
                    "deployment_suffix": deployment_suffix,
                }
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
                template=create_rollup_parameters_template, data={
                    "zkevm_rollup_chain_id": zkevm_rollup_chain_id,
                    "zkevm_rollup_fork_id": zkevm_rollup_fork_id,
                    "zkevm_rollup_consensus": zkevm_rollup_consensus,
                    "zkevm_l2_admin_address": zkevm_l2_admin_address,
                    "zkevm_l2_admin_private_key": zkevm_l2_admin_private_key,
                    "zkevm_l2_sequencer_address": zkevm_l2_sequencer_address,
                    "zkevm_l2_aggregator_address": zkevm_l2_aggregator_address,
                    "zkevm_rpc_http_port": zkevm_rpc_http_port,
                    "deployment_suffix": deployment_suffix,
                }
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
                template=contract_deployment_script_template, data={
                    "l1_rpc_url": l1_rpc_url,
                    "l1_preallocated_mnemonic": l1_preallocated_mnemonic,
                    "zkevm_rollup_fork_id": zkevm_rollup_fork_id,
                    "zkevm_l2_admin_address": zkevm_l2_admin_address,
                    "zkevm_l2_admin_private_key": zkevm_l2_admin_private_key,
                    "zkevm_l2_sequencer_address": zkevm_l2_sequencer_address,
                    "zkevm_l2_sequencer_private_key": zkevm_l2_sequencer_private_key,
                    "zkevm_l2_aggregator_address": zkevm_l2_aggregator_address,
                    "zkevm_l2_claimtxmanager_address": zkevm_l2_claimtxmanager_address,
                    "zkevm_l2_agglayer_address": zkevm_l2_agglayer_address,
                    "zkevm_l2_dac_address": zkevm_l2_dac_address,
                    "zkevm_dac_port": zkevm_dac_port,
                    "deployment_suffix": deployment_suffix,
                }
            )
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
                template=create_keystores_script_template, data={
                    "zkevm_l2_sequencer_private_key": zkevm_l2_sequencer_private_key,
                    "zkevm_l2_aggregator_private_key": zkevm_l2_aggregator_private_key,
                    "zkevm_l2_agglayer_private_key": zkevm_l2_agglayer_private_key,
                    "zkevm_l2_dac_private_key": zkevm_l2_dac_private_key,
                    "zkevm_l2_claimtxmanager_private_key": zkevm_l2_claimtxmanager_private_key,
                    "zkevm_l2_proofsigner_private_key": zkevm_l2_proofsigner_private_key,
                    "zkevm_l2_keystore_password": zkevm_l2_keystore_password,
                }
            )
        },
    )

    # Create helper service to deploy contracts
    contracts_service_name = "contracts" + deployment_suffix
    zkevm_contracts_image = "{}:fork{}".format(
        zkevm_contracts_image, zkevm_rollup_fork_id
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
