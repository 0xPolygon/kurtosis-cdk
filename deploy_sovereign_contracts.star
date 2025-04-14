def run(plan, args, l1_op_contract_addresses, predeployed_contracts=False):
    # Provide L1 OP addresses to the sovereign setup script as an environment variable.
    l1_op_addresses = ";".join(list(l1_op_contract_addresses.values()))

    script = "/opt/contract-deploy/run-sovereign-setup.sh"
    if predeployed_contracts:
        script = "/opt/contract-deploy/run-sovereign-setup-predeployed.sh"

    plan.exec(
        description="Deploying sovereign contracts on OP Stack",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && L1_OP_ADDRESSES='{1}' {0}".format(
                    script, l1_op_addresses
                ),
            ]
        ),
    )
