aggchain_vkey = import_module("./src/vkey/aggchain.star")
agglayer_vkey = import_module("./src/vkey/agglayer.star")
constants = import_module("./src/package_io/constants.star")
data_availability_package = import_module("./lib/data_availability.star")

BYTES32_ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000"

INPUTS = [
    {
        "name": "create_new_rollup.json",
        "file": "./templates/sovereign-rollup/create_new_rollup.json",
    },
    {
        "name": "op-custom-genesis-addresses.json",
        "file": "./templates/sovereign-rollup/op-custom-genesis-addresses.json",
    },
    {
        "name": "deploy_parameters.json",
        "file": "./templates/contract-deploy/deploy_parameters.json",
    },
    {
        "name": "cdk-erigon-custom-genesis-addresses.json",
        "file": "./templates/cdk-erigon/cdk-erigon-custom-genesis-addresses.json",
    },
    {
        "name": "create_rollup_parameters.json",
        "file": "./templates/contract-deploy/create_rollup_parameters.json",
    },
]

ARTIFACTS = [
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
        "name": "json2http.py",
        "file": "./scripts/json2http.py",
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
    if args["consensus_contract_type"] == constants.CONSENSUS_TYPE.ecdsa_multisig:
        aggchain_vkey_selector = "0x00000000"
    else:
        aggchain_vkey_selector = aggchain_vkey.get_selector(plan, aggkit_prover_image)

    # Set program vkey based on the consensus type.
    # For non pessimistic consensus types, we use the bytes32 zero hash.
    # For pessimistic consensus types, we use the pessimistic vkey hash.
    program_vkey = pp_vkey_hash
    if args.get("consensus_contract_type") in [
        constants.CONSENSUS_TYPE.rollup,
        constants.CONSENSUS_TYPE.cdk_validium,
        constants.CONSENSUS_TYPE.ecdsa_multisig,
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
                        "is_vanilla_client": is_vanilla_client(args, deployment_stages),
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

    # Dump input params to input_args.json file
    json_str = json.encode(
        {
            "args": args,
            "deployment_stages": deployment_stages,
            "op_stack_args": op_stack_args,
        }
    )
    pretty_str = json.indent(json_str)
    artifact = plan.render_templates(
        name="input_args.json",
        config={
            "input_args.json": struct(
                template="{{ . }}",
                data=pretty_str,
            ),
        },
    )
    artifacts.append(artifact)

    template_data = args | {
        "is_cdk_validium": data_availability_package.is_cdk_validium(args),
        "is_vanilla_client": is_vanilla_client(args, deployment_stages),
        "deploy_op_succinct": deployment_stages.get("deploy_op_succinct", False),
        "zkevm_rollup_consensus": data_availability_package.get_consensus_contract(
            args
        ),
        "deploy_optimism_rollup": deployment_stages.get(
            "deploy_optimism_rollup", False
        ),
        "op_stack_seconds_per_slot": op_stack_args["optimism_package"]["chains"][0][
            "network_params"
        ]["seconds_per_slot"],
        # vkeys and selectors
        "pp_vkey_hash": pp_vkey_hash,
        "pp_vkey_selector": pp_vkey_selector,
        "aggchain_vkey_hash": aggchain_vkey_hash,
        "aggchain_vkey_selector": aggchain_vkey_selector,
        "program_vkey": program_vkey,
    }

    input_artifacts = []
    for artifact_cfg in list(INPUTS):
        artifact = plan.render_templates(
            name=artifact_cfg["name"],
            config={
                artifact_cfg["name"]: struct(
                    template=read_file(src=artifact_cfg["file"]), data=template_data
                )
            },
        )
        input_artifacts.append(artifact)

    scripts_artifacts = [
        plan.render_templates(
            name="contracts.sh",
            config={
                "contracts.sh": struct(
                    template=read_file(src="./templates/contracts/contracts.sh"),
                    data=template_data,
                )
            },
        )
    ]

    succinct_artifacts = []

    # Create op-succinct artifacts
    if deployment_stages.get("deploy_op_succinct", False):
        fetch_rollup_config_artifact = plan.get_files_artifact(
            name="fetch-l2oo-config",
            description="Get fetch-l2oo-config files artifact",
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

        succinct_artifacts.append(fetch_rollup_config_artifact)
        scripts_artifacts.append(deploy_op_succinct_contract_artifact)

    # Base file artifacts to mount regardless of deployment type
    files = {
        # These are filled as result of script execution:
        "/opt/keystores": Directory(persistent_key="keystores"),
        "/opt/output": Directory(persistent_key="output"),
        # Content are made available to script here:
        "/opt/input": Directory(artifact_names=input_artifacts),
        "/opt/scripts": Directory(artifact_names=scripts_artifacts),
        # Legacy folders (WIP):
        "/opt/zkevm": Directory(persistent_key="zkevm-artifacts"),
        "/opt/contract-deploy/": Directory(artifact_names=artifacts),
    }
    if succinct_artifacts:
        # Mount op-succinct specific artifacts
        files["/opt/op-succinct/"] = Directory(artifact_names=succinct_artifacts)

    # Create helper service to deploy contracts
    contracts_service_name = "contracts" + args["deployment_suffix"]
    plan.add_service(
        name=contracts_service_name,
        config=ServiceConfig(
            image=args["agglayer_contracts_image"],
            ports={"http": PortSpec(8080, application_protocol="http", wait=None)},
            files=files,
            # These two lines are only necessary to deploy to any Kubernetes environment (e.g. GKE).
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
            user=User(uid=0, gid=0),  # Run the container as root user.
        ),
    )
    plan.exec(
        description="JSON 2 Http Server",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "gunicorn --bind 0.0.0.0:8080 json2http:app --chdir /opt/contract-deploy --daemon || true",
            ]
        ),
    )

    # Set permissions for contracts script
    plan.exec(
        description="Setting permissions for /opt/scripts/contracts.sh",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "chmod +x /opt/scripts/contracts.sh"]
        ),
    )

    # Create keystores.
    plan.exec(
        description="Creating keystores for zkevm-node/cdk-validium components",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "/opt/scripts/contracts.sh create_keystores"]
        ),
    )

    # Deploy contracts.
    if (
        args.get("l1_custom_genesis")
        and args.get("consensus_contract_type") == constants.CONSENSUS_TYPE.pessimistic
    ):
        plan.print(
            "Skipping L1 smart contract deployment: using custom genesis in pessimistic mode"
        )
        plan.exec(
            description="Configuring contract container for pessimistic",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "/opt/scripts/contracts.sh configure_contract_container_custom_genesis",
                ]
            ),
        )
    elif args.get("l1_custom_genesis") and (
        args.get("consensus_contract_type") == constants.CONSENSUS_TYPE.cdk_validium
        or args.get("consensus_contract_type") == constants.CONSENSUS_TYPE.rollup
    ):
        plan.print("Skipping L1 smart contract deployment: custom genesis is enabled")
        plan.exec(
            description="Configuring contract container for rollup/cdk-validium",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "/opt/scripts/contracts.sh configure_contract_container_custom_genesis_cdk_erigon",
                ]
            ),
        )
        plan.exec(
            description="Deploying rollup smc on L1",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "/opt/scripts/contracts.sh create_agglayer_rollup",
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
        plan.exec(
            description="Deploying Agglayer smart contracts on L1",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "/opt/scripts/contracts.sh deploy_agglayer_core_contracts",
                ]
            ),
        )
        plan.exec(
            description="Creating rollup on L1",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "/opt/scripts/contracts.sh create_agglayer_rollup",
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
                "/opt/scripts/contracts.sh update_ger",
            ]
        ),
    )


def is_vanilla_client(args, deployment_stages):
    if (
        args["consensus_contract_type"] == constants.CONSENSUS_TYPE.ecdsa_multisig
        and deployment_stages.get("deploy_optimism_rollup") == True
    ):
        return True
    else:
        return False
