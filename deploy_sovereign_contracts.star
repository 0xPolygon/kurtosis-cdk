def run(plan, args, predeployed_contracts=False):
    if args.get("l1_custom_genesis"):
        return

    script = "/opt/contract-deploy/run-sovereign-setup.sh"
    if predeployed_contracts:
        plan.print("Predeployed contracts detected. Using predeployed setup script.")
        script = "/opt/contract-deploy/run-sovereign-setup-predeployed.sh"

    plan.exec(
        description="Creating rollup type and rollup on L1",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format(script),
            ]
        ),
    )


def init_rollup(plan, args, deployment_stages):
    if deployment_stages.get("deploy_op_succinct", False):
        l2oo_config = get_l2_oo_config(plan, args)
        plan.print(l2oo_config)
        plan.exec(
            description="Copying opsuccinctl2ooconfig.json to contracts image",
            service_name="contracts" + args["deployment_suffix"],
            recipe=ExecRecipe(
                command=[
                    "/bin/sh",
                    "-c",
                    "echo '"
                    + l2oo_config
                    + "' > /opt/contract-deploy/opsuccinctl2ooconfig.json",
                ]
            ),
        )

    plan.exec(
        description="Running rollup initialization",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "/opt/scripts/contracts.sh initialize_rollup",
            ]
        ),
    )


def get_l2_oo_config(plan, args):
    return """
{{
    "challenger": "{}",
    "finalizationPeriod": {},
    "l2BlockTime": {},
    "opSuccinctL2OutputOracleImpl": "{}",
    "owner": "{}",
    "proposer": "{}",
    "rollupConfigHash": "{}",
    "startingBlockNumber": {},
    "startingOutputRoot": "{}",
    "startingTimestamp": {},
    "submissionInterval": {},
    "verifier": "{}",
    "aggregationVkey": "{}",
    "rangeVkeyCommitment": "{}",
    "proxyAdmin": "{}"
}}""".format(
        args["sp1_challenger"],
        args["sp1_finalization_period"],
        args["sp1_l2_block_time"],
        args["sp1_l2_output_oracle_impl"],
        args["sp1_owner"],
        args["sp1_proposer"],
        args["sp1_rollup_config_hash"],
        args["sp1_starting_block_number"],
        args["sp1_starting_output_root"],
        args["sp1_starting_timestamp"],
        args["sp1_submission_interval"],
        args["sp1_verifier"],
        args["sp1_aggregation_vkey"],
        args["sp1_range_vkey_commitment"],
        args["sp1_proxy_admin"],
    )


def fund_addresses(plan, args, contract_addresses, rpc_url):
    # Provide L1 OP addresses to the sovereign setup script as an environment variable.
    contract_addresses_to_fund = ";".join(
        [contract_addresses[key] for key in contract_addresses]
    )
    env_vars = {
        "ADDRESSES_TO_FUND": contract_addresses_to_fund,
        "RPC_URL": rpc_url,
        "L2_FUNDING_AMOUNT": args.get("l2_funding_amount", "0.1ether"),
        "DEPLOYMENT_SUFFIX": args["deployment_suffix"],
    }

    # Only set L1_PREALLOCATED_MNEMONIC if provided and not using the default RPC
    if (
        rpc_url
        != "http://op-el-1-op-geth-op-node" + args["deployment_suffix"] + ":8545"
        and "l1_preallocated_mnemonic" in args
    ):
        env_vars["L1_PREALLOCATED_MNEMONIC"] = args["l1_preallocated_mnemonic"]

    # Build env_string with double quotes around values to handle semicolons
    env_string = " ".join(['{}="{}"'.format(key, env_vars[key]) for key in env_vars])
    command = [
        "/bin/bash",
        "-c",
        "{0} {1}".format(env_string, "/opt/scripts/contracts.sh fund_addresses"),
    ]

    plan.exec(
        description="Deploying sovereign contracts on OP Stack",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(command=command),
    )
