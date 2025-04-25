constants = import_module("./src/package_io/constants.star")
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

    # Get vkeys.
    (pp_vkey_hash, pp_vkey_selector) = get_agglayer_vkeys(plan, args)
    deploy_optimism_rollup = deployment_stages.get("deploy_optimism_rollup", False)
    (aggchain_vkey_hash, aggchain_vkey_version) = get_aggchain_vkeys(
        plan, args, deploy_optimism_rollup
    )
    plan.print("pp_vkey_hash: {}".format(pp_vkey_hash))
    plan.print("pp_vkey_selector: {}".format(pp_vkey_selector))
    plan.print("aggchain_vkey_hash: {}".format(aggchain_vkey_hash))
    plan.print("aggchain_vkey_version: {}".format(aggchain_vkey_version))

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
                        # vkeys
                        "pp_vkey_hash": pp_vkey_hash,
                        "pp_vkey_selector": pp_vkey_selector,
                        "aggchain_vkey_hash": aggchain_vkey_hash,
                        "aggchain_vkey_version": aggchain_vkey_version,
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


def get_agglayer_vkeys(plan, args):
    # The pp vkey and pp vkey selector are used by the 3_deployContracts script that performs
    # the initial setup of the rollup manager.
    pp_vkey_hash = constants.ZERO_HASH
    pp_vkey_selector = "0x00000001"

    consensus_type = args.get("consensus_contract_type")
    if consensus_type in [
        constants.CONSENSUS_TYPE.pessimistic,
        constants.CONSENSUS_TYPE.ecdsa,
        constants.CONSENSUS_TYPE.fep,
    ]:
        agglayer_image = args.get("agglayer_image")
        pp_vkey_hash = get_agglayer_vkey_hash(plan, image=agglayer_image)
        pp_vkey_selector = get_agglayer_vkey_selector(plan, image=agglayer_image)

    return (pp_vkey_hash, pp_vkey_selector)


def get_agglayer_vkey_hash(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-hash-getter",
        description="Getting agglayer vkey hash",
        image=image,
        run="agglayer vkey | tr -d '\n'",
    )
    return result.output


def get_agglayer_vkey_selector(plan, image):
    result = plan.run_sh(
        name="agglayer-vkey-selector-getter",
        description="Getting agglayer vkey selector",
        image=image,
        run="agglayer vkey-selector | tr -d '\n'",
    )
    # FIXME: The agglayer vkey selector may include a 0x prefix in the future and we'll need to fix thi
    return "0x{}".format(result.output)


def get_aggchain_vkeys(plan, args, deploy_optimism_rollup):
    # The aggchain vkey hash and aggchain vkey version are used to initialize a new sovereign rollup.
    aggchain_vkey_hash = None
    aggchain_vkey_version = None

    consensus_type = args.get("consensus_contract_type")
    if (
        consensus_type
        in [
            constants.CONSENSUS_TYPE.pessimistic,
            constants.CONSENSUS_TYPE.ecdsa,
            constants.CONSENSUS_TYPE.fep,
        ]
        and deploy_optimism_rollup
    ):
        aggkit_prover_image = args.get("aggkit_prover_image")
        aggchain_vkey_hash = get_aggchain_vkey_hash(plan, image=aggkit_prover_image)
        aggchain_vkey_version = get_aggchain_vkey_version(
            plan, image=aggkit_prover_image
        )

    return (aggchain_vkey_hash, aggchain_vkey_version)


def get_aggchain_vkey_hash(plan, image):
    result = plan.run_sh(
        name="aggchain-vkey-hash-getter",
        description="Getting aggchain vkey hash",
        image=image,
        run="aggkit-prover vkey | tr -d '\n'",
    )
    # FIXME: The aggchain vkey hash may include a 0x prefix in the future and we'll need to fix this.
    return "0x{}".format(result.output)


def get_aggchain_vkey_version(plan, image):
    result = plan.run_sh(
        name="aggchain-vkey-version-getter",
        description="Getting aggchain vkey version",
        image=image,
        run="aggkit-prover vkey-selector | tr -d '\n'",
    )
    # FIXME: The aggchain vkey version may include a 0x prefix in the future and we'll need to fix this.
    return "0x{}".format(result.output)
