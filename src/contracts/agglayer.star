aggchain_vkey = import_module("../vkey/aggchain.star")
agglayer_vkey = import_module("../vkey/agglayer.star")
constants = import_module("../package_io/constants.star")
contracts_util = import_module("./util.star")
cdk_data_availability = import_module("../chain/cdk-erigon/cdk_data_availability.star")
ports_package = import_module("../chain/shared/ports.star")


BYTES32_ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000"

INPUTS = [
    {
        "name": "create_new_rollup.json",
        "file": "../../static_files/contracts/sovereign-rollup/create_new_rollup.json",
    },
    {
        "name": "op-custom-genesis-addresses.json",
        "file": "../../static_files/contracts/sovereign-rollup/op-custom-genesis-addresses.json",
    },
    {
        "name": "deploy_parameters.json",
        "file": "../../static_files/contracts/deploy_parameters.json",
    },
    {
        "name": "cdk-erigon-custom-genesis-addresses.json",
        "file": "../../static_files/contracts/cdk-erigon/custom-genesis-addresses.json",
    },
    {
        "name": "create_rollup_parameters.json",
        "file": "../../static_files/contracts/create_rollup_parameters.json",
    },
    {
        "name": "add_rollup_type.json",
        "file": "../../static_files/contracts/sovereign-rollup/add_rollup_type.json",
    },
    {
        "name": "create-genesis-sovereign-params.json",
        "file": "../../static_files/contracts/sovereign-rollup/create-genesis-sovereign-params.json",
    },
]


def run(plan, args, deployment_stages, op_stack_args):
    inputs_list = list(INPUTS)

    # If we are configured to use a previous deployment, we'll
    # dynamically add artifacts for the genesis and combined outputs.
    if args.get("use_previously_deployed_contracts"):
        inputs_list.append(
            {
                "name": "combined.json",
                "file": "../../templates/contract-deploy/combined.json",
            }
        )
        inputs_list.append(
            {
                "name": "dynamic-" + args["chain_name"] + "-conf.json",
                "file": "../../templates/contract-deploy/dynamic-"
                + args["chain_name"]
                + "-conf.json",
            }
        )
        inputs_list.append(
            {
                "name": "dynamic-" + args["chain_name"] + "-allocs.json",
                "file": "../../templates/contract-deploy/dynamic-"
                + args["chain_name"]
                + "-allocs.json",
            }
        )

    # Retrieve vkeys and vkey selectors from the binaries.
    # Note: These are runtime values (futures) but Kurtosis handles them correctly
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

    chains = op_stack_args.get("optimism_package").get("chains")
    chain1_name = chains.keys()[0]
    chain1 = chains.get(chain1_name)
    op_stack_seconds_per_slot = chain1["network_params"]["seconds_per_slot"]

    consensus_contract = constants.CONSENSUS_TYPE_TO_CONTRACT_MAPPING.get(
        args["consensus_contract_type"]
    )

    template_data = args | {
        "is_vanilla_client": is_vanilla_client(args, deployment_stages),
        "deploy_op_succinct": deployment_stages.get("deploy_op_succinct", False),
        "consensus_contract": consensus_contract,
        "sequencer_type": args["sequencer_type"],
        "op_stack_seconds_per_slot": op_stack_seconds_per_slot,
        # vkeys and selectors
        "pp_vkey_hash": pp_vkey_hash,
        "pp_vkey_selector": pp_vkey_selector,
        "aggchain_vkey_hash": aggchain_vkey_hash,
        "aggchain_vkey_selector": aggchain_vkey_selector,
        "program_vkey": program_vkey,
        "contracts_dir": constants.CONTRACTS_DIR,
        "keystores_dir": constants.KEYSTORES_DIR,
        "output_dir": constants.OUTPUT_DIR,
        "input_dir": constants.INPUT_DIR,
        "scripts_dir": constants.SCRIPTS_DIR,
        "cdk_data_availability_rpc_port_number": cdk_data_availability.RPC_PORT_NUMBER,
        "http_rpc_port_number": ports_package.HTTP_RPC_PORT_NUMBER,
    }

    input_artifacts = []
    for artifact_cfg in inputs_list:
        artifact = plan.render_templates(
            name=artifact_cfg["name"],
            config={
                artifact_cfg["name"]: struct(
                    template=read_file(src=artifact_cfg["file"]), data=template_data
                )
            },
        )
        input_artifacts.append(artifact)

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
    input_artifacts.append(artifact)

    scripts_artifacts = [
        plan.render_templates(
            name="contracts.sh",
            config={
                "contracts.sh": struct(
                    template=read_file(src="../../static_files/contracts/contracts.sh"),
                    data=template_data,
                )
            },
        ),
        plan.upload_files(
            src="../../static_files/contracts/create_op_allocs.py",
            name="create_op_allocs.py",
            description="Uploading create_op_allocs.py artifact",
        ),
        plan.upload_files(
            src="../../static_files/contracts/json2http.py",
            name="json2http.py",
            description="Uploading json2http.py artifact",
        ),
    ]

    l1_artifacts = []
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
                        src="../../static_files/chain/op-geth/op-succinct-proposer/deploy-op-succinct-contracts.sh"
                    ),
                    data=args,
                ),
            },
            description="Create deploy_op_succinct_contract files artifact",
        )
        l1_genesis_artifact = plan.get_files_artifact(
            name="el_cl_genesis_data_for_op_succinct",
            description="Get L1 genesis file for op-succinct",
        )

        succinct_artifacts.append(fetch_rollup_config_artifact)
        scripts_artifacts.append(deploy_op_succinct_contract_artifact)
        l1_artifacts.append(l1_genesis_artifact)

    # Base file artifacts to mount regardless of deployment type
    files = {
        # These are filled as result of script execution:
        constants.KEYSTORES_DIR: Directory(persistent_key="keystores-artifact"),
        constants.OUTPUT_DIR: Directory(persistent_key="output-artifact"),
        # Content are made available to script here:
        constants.INPUT_DIR: Directory(artifact_names=input_artifacts),
        constants.SCRIPTS_DIR: Directory(artifact_names=scripts_artifacts),
    }
    if succinct_artifacts:
        # Mount op-succinct specific artifacts
        files["/opt/op-succinct/"] = Directory(artifact_names=succinct_artifacts)
        files["/configs/L1"] = Directory(artifact_names=[l1_genesis_artifact])

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
                "gunicorn --bind 0.0.0.0:8080 json2http:app --chdir {} --daemon || true".format(
                    constants.SCRIPTS_DIR
                ),
            ]
        ),
    )

    # Set permissions for contracts script
    plan.exec(
        description="Setting permissions for {}/contracts.sh".format(
            constants.SCRIPTS_DIR
        ),
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {}/contracts.sh".format(constants.SCRIPTS_DIR),
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
                "{}/contracts.sh create_keystores".format(constants.SCRIPTS_DIR),
            ]
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
                    "{}/contracts.sh configure_contract_container_custom_genesis".format(
                        constants.SCRIPTS_DIR
                    ),
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
                    "{}/contracts.sh configure_contract_container_custom_genesis_cdk_erigon".format(
                        constants.SCRIPTS_DIR
                    ),
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
                    "{}/contracts.sh create_agglayer_rollup".format(
                        constants.SCRIPTS_DIR
                    ),
                ]
            ),
        )
        # Store CDK configs.
        plan.store_service_files(
            name="cdk-erigon-chain-config",
            service_name="contracts" + args["deployment_suffix"],
            src=constants.OUTPUT_DIR + "/dynamic-" + args["chain_name"] + "-conf.json",
        )

        plan.store_service_files(
            name="cdk-erigon-chain-allocs",
            service_name="contracts" + args["deployment_suffix"],
            src=constants.OUTPUT_DIR
            + "/dynamic-"
            + args["chain_name"]
            + "-allocs.json",
        )
        plan.store_service_files(
            name="cdk-erigon-chain-first-batch",
            service_name="contracts" + args["deployment_suffix"],
            src=constants.OUTPUT_DIR + "/first-batch-config.json",
        )
    else:
        plan.exec(
            description="Deploying Agglayer smart contracts on L1",
            service_name=contracts_service_name,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "{}/contracts.sh deploy_agglayer_core_contracts".format(
                        constants.SCRIPTS_DIR
                    ),
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
                    "{}/contracts.sh create_agglayer_rollup".format(
                        constants.SCRIPTS_DIR
                    ),
                ]
            ),
        )
        # Store CDK configs.
        plan.store_service_files(
            name="cdk-erigon-chain-config",
            service_name="contracts" + args["deployment_suffix"],
            src=constants.OUTPUT_DIR + "/dynamic-" + args["chain_name"] + "-conf.json",
        )

        plan.store_service_files(
            name="cdk-erigon-chain-allocs",
            service_name="contracts" + args["deployment_suffix"],
            src=constants.OUTPUT_DIR
            + "/dynamic-"
            + args["chain_name"]
            + "-allocs.json",
        )
        plan.store_service_files(
            name="cdk-erigon-chain-first-batch",
            service_name="contracts" + args["deployment_suffix"],
            src=constants.OUTPUT_DIR + "/first-batch-config.json",
        )

    # Force update GER.
    plan.exec(
        description="Updating the GER so the L1 Info Tree Index is greater than 0",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "{}/contracts.sh update_ger".format(constants.SCRIPTS_DIR),
            ]
        ),
    )


def is_vanilla_client(args, deployment_stages):
    if (
        args["consensus_contract_type"] == constants.CONSENSUS_TYPE.ecdsa_multisig
        and args["sequencer_type"] == constants.SEQUENCER_TYPE.op_geth
    ):
        return True
    else:
        return False


# Called from main for erigon stacks
def l2_legacy_fund_accounts(plan, args):
    l2_rpc_url = contracts_util.get_l2_rpc_url(plan, args)
    contracts_service_name = "contracts" + args["deployment_suffix"]
    env_string = "l2_rpc_url={0}".format(l2_rpc_url.http)

    plan.exec(
        description="Funding accounts on L2",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "{0} {1}".format(
                    env_string,
                    "{}/contracts.sh l2_legacy_fund_accounts".format(
                        constants.SCRIPTS_DIR
                    ),
                ),
            ]
        ),
    )


# Called from main for erigon stacks
def deploy_l2_contracts(plan, args):
    l2_rpc_url = contracts_util.get_l2_rpc_url(plan, args)
    contracts_service_name = "contracts" + args["deployment_suffix"]
    env_string = "l2_rpc_url={0}".format(l2_rpc_url.http)

    # When funding accounts and deploying the contracts on l2, the
    # contracts service is reused to reduce startup time. Since the l2
    # doesn't exist at the time the service is added to kurtosis, the
    # `l2_rpc_url` can't be templated. Therefore, the `l2_rpc_url` is exported
    # as an environment variable before running the script.

    plan.exec(
        description="Deploying contracts on L2",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/bash",
                "-c",
                "{0} {1}".format(
                    env_string,
                    "{}/contracts.sh l2_contract_setup".format(constants.SCRIPTS_DIR),
                ),
            ]
        ),
    )


# Called from main when optimism rollup
def create_sovereign_predeployed_genesis(plan, args):
    contracts_service_name = "contracts" + args["deployment_suffix"]

    plan.exec(
        description="Creating sovereign predeployed Genesis for OP Stack",
        service_name=contracts_service_name,
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "{}/contracts.sh create_predeployed_op_genesis".format(
                    constants.SCRIPTS_DIR
                ),
            ]
        ),
    )

    allocs_file = "predeployed_allocs.json"

    plan.store_service_files(
        service_name=contracts_service_name,
        name=allocs_file,
        src=constants.OUTPUT_DIR + "/" + allocs_file,
        description="Storing {}".format(allocs_file),
    )
