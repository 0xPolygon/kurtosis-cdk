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
]


def run(plan, args):
    artifacts = []
    for artifact_cfg in ARTIFACTS:
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
                        "zkevm_rollup_consensus": data_availability_package.get_consensus_contract(
                            args
                        ),
                    },
                )
            },
        )
        artifacts.append(artifact)

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
    cdk_erigon_node_chain_config_artifact = plan.store_service_files(
        name="cdk-erigon-node-chain-config",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/dynamic-kurtosis-conf.json",
    )

    cdk_erigon_node_chain_allocs_artifact = plan.store_service_files(
        name="cdk-erigon-node-chain-allocs",
        service_name="contracts" + args["deployment_suffix"],
        src="/opt/zkevm/dynamic-kurtosis-allocs.json",
    )
