def run(plan, args, predeployed_contracts=False):
    script = "/opt/contract-deploy/run-sovereign-setup.sh"
    if predeployed_contracts:
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
    script = "/opt/contract-deploy/run-initialize-rollup.sh"

    plan.exec(
        description="Running rollup initialization",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format(script),
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


def fund_addresses(plan, args, l1_op_contract_addresses):
    # Provide L1 OP addresses to the sovereign setup script as an environment variable.
    l1_op_addresses = ";".join(list(l1_op_contract_addresses.values()))

    plan.exec(
        description="Deploying sovereign contracts on OP Stack",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && L1_OP_ADDRESSES='{1}' {0}".format(
                    "/opt/contract-deploy/fund-addresses.sh",
                    l1_op_addresses,
                ),
            ]
        ),
    )
