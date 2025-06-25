aggchain_vkey = import_module("./src/vkey/aggchain.star")
agglayer_vkey = import_module("./src/vkey/agglayer.star")
constants = import_module("./src/package_io/constants.star")
data_availability_package = import_module("./lib/data_availability.star")

BYTES32_ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000"

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
        "name": "run-l1-contract-setup.sh",
        "file": "./templates/contract-deploy/run-l1-contract-setup.sh",
    },
    {
        "name": "run-l1-2-contract-setup.sh",
        "file": "./templates/contract-deploy/run-l1-2-contract-setup.sh",
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
    {
        "name": "op-configure-contract-container-custom-genesis.sh",
        "file": "./templates/sovereign-rollup/op-configure-contract-container-custom-genesis.sh",
    },
    {
        "name": "configure-contract-container-custom-genesis.sh",
        "file": "./templates/cdk-erigon/configure-contract-container-custom-genesis.sh",
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

    # Retrieve vkeys and vkey selectors from the binaries.
    agglayer_image = args.get("agglayer_image")
    pp_vkey_hash = agglayer_vkey.get_hash(plan, agglayer_image)
    plan.print(
        "Agglayer vkey hash: {}".format(pp_vkey_hash),
    )
    pp_vkey_selector = agglayer_vkey.get_selector(plan, agglayer_image)
    plan.print(
        "Agglayer vkey selector: {}".format(pp_vkey_selector),
    )

    aggkit_prover_image = args.get("aggkit_prover_image")
    aggchain_vkey_hash = aggchain_vkey.get_hash(plan, aggkit_prover_image)
    aggchain_vkey_selector = aggchain_vkey.get_selector(plan, aggkit_prover_image)

    # Set program vkey based on the consensus type.
    # For non pessimistic consensus types, we use the bytes32 zero hash.
    # For pessimistic consensus types, we use the pessimistic vkey hash.
    program_vkey = pp_vkey_hash
    if args.get("consensus_contract_type") in [
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
    ]:
        program_vkey = BYTES32_ZERO_HASH

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
                        # vkeys and selectors
                        "pp_vkey_hash": pp_vkey_hash,
                        "pp_vkey_selector": pp_vkey_selector,
                        "aggchain_vkey_hash": aggchain_vkey_hash,
                        "aggchain_vkey_selector": aggchain_vkey_selector,
                        "program_vkey": program_vkey,
                    },
                )
            },
        )
        artifacts.append(artifact)

    # Base file artifacts to mount regardless of deployment type
    files = {
        "/opt/zkevm": Directory(persistent_key="zkevm-artifacts"),
        "/opt/contract-deploy/": Directory(artifact_names=artifacts),
    }

    # Create op-succinct artifacts
    if deployment_stages.get("deploy_op_succinct", False):
        fetch_rollup_config_artifact = plan.get_files_artifact(
            name="fetch-rollup-config",
            description="Get fetch-rollup-config files artifact",
        )
        deploy_op_succinct_contract_artifact = plan.render_templates(
            name="deploy-op-succinct-contracts.sh",
            config={
                "deploy-op-succinct-contracts.sh": struct(
                    template=read_file(
                        src="./templates/op-succinct/deploy-op-succinct-contracts.sh"
                    ),
                    data=args,
                ),
            },
            description="Create deploy_op_succinct_contract files artifact",
        )
        # Mount op-succinct specific artifacts
        files["/opt/op-succinct/"] = Directory(
            artifact_names=[fetch_rollup_config_artifact]
        )
        files["/opt/scripts/"] = Directory(
            artifact_names=[deploy_op_succinct_contract_artifact]
        )

    # Create helper service to deploy contracts
    contracts_service_name = "contracts" + args["deployment_suffix"]
    plan.add_service(
        name=contracts_service_name,
        config=ServiceConfig(
            image=args["zkevm_contracts_image"],
            files=files,
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )

    # Deploy contracts.
    if args.get("custom_genesis") == True and args.get("consensus_contract_type") == constants.CONSENSUS_TYPE.pessimistic:
        plan.print("Skipping L1 smc deployment as custom genesis is set to true for pessimistic mode...")
        # We need to create the combined.json file
        plan.exec(
            description="Creating combined file for pessimistic",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                r"""cat >/opt/zkevm/combined.json <<'EOF'
    {
      "polygonRollupManagerAddress": "0xFB054898a55bB49513D1BA8e0FB949Ea3D9B4153",
      "polygonZkEVMBridgeAddress":   "0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7",
      "polygonZkEVMGlobalExitRootAddress": "0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2",
      "aggLayerGatewayAddress":      "0x6c6c009cC348976dB4A908c92B24433d4F6edA43",
      "pessimisticVKeyRouteALGateway": {
        "pessimisticVKeySelector": "0x00000002",
        "verifier":                "0xf22E2B040B639180557745F47aB97dFA95B1e22a",
        "pessimisticVKey":         "0x00e60517ac96bf6255d81083269e72c14ad006e5f336f852f7ee3efb91b966be"
      },
      "polTokenAddress":            "0xEdE9cf798E0fE25D35469493f43E88FeA4a5da0E",
      "zkEVMDeployerContract":      "0x1b50e2F3bf500Ab9Da6A7DBb6644D392D9D14b99",
      "deployerAddress":            "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
      "timelockContractAddress":    "0x3D4C5989214ca3CDFf9e62778cDD56a94a05348D",
      "deploymentRollupManagerBlockNumber": 0,
      "upgradeToULxLyBlockNumber":          0,
      "admin":                 "0xE34aaF64b29273B7D567FCFc40544c014EEe9970",
      "trustedAggregator":      "0xCae5b68Ff783594bDe1b93cdE627c741722c4D4d",
      "proxyAdminAddress":      "0xd60F1BCf5566fCCD62f8AA3bE00525DdA6Ab997c",
      "salt":                   "0x0000000000000000000000000000000000000000000000000000000000000001",
      "polygonZkEVML2BridgeAddress":        "0x927aa8656B3a541617Ef3fBa4A2AB71320dc7fD7",
      "polygonZkEVMGlobalExitRootL2Address": "0xa40d5f56745a118d0906a34e69aec8c0db1cb8fa",
      "bridgeGenBlockNumber":               0
    }
    """
            ]
            ),
        )
        
        plan.exec(
            description="Configuring contract container for pessimistic...",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format("/opt/contract-deploy/op-configure-contract-container-custom-genesis.sh")
            ]
            ),
        )
    elif args.get("custom_genesis") == True and args.get("consensus_contract_type") == constants.CONSENSUS_TYPE.cdk_validium:
        plan.print("Skipping L1 smc deployment as custom genesis is set to true...")        
        plan.exec(
            description="Configuring contract container for cdk-validium...",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format("/opt/contract-deploy/configure-contract-container-custom-genesis.sh")
            ]
            ),
        )
        plan.print("Deploying rollup smc on L1...")
        plan.exec(
            description="Deploying rollup smc on L1",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "chmod +x {0} && {0}".format(
                        "/opt/contract-deploy/run-l1-2-contract-setup.sh"
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
    else:
        plan.print("Deploying L1 smc...")
        plan.exec(
            description="Deploying contracts on L1",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "chmod +x {0} && {0}".format(
                        "/opt/contract-deploy/run-l1-contract-setup.sh"
                    ),
                ]
            ),
        )
        plan.print("Deploying rollup smc on L1...")
        plan.exec(
            description="Deploying rollup smc on L1",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "chmod +x {0} && {0}".format(
                        "/opt/contract-deploy/run-l1-2-contract-setup.sh"
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
