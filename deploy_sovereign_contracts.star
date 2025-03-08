def run(plan, args, l1_op_contract_addresses):
    # Provide L1 OP addresses to the sovereign setup script as an environment variable.
    l1_op_addresses = ";".join(
        [l1_op_contract_addresses[key] for key in l1_op_contract_addresses]
    )
    plan.exec(
        description="Deploying sovereign contracts on OP Stack",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && L1_OP_ADDRESSES='{1}' {0}".format(
                    "/opt/contract-deploy/run-sovereign-setup.sh", l1_op_addresses
                ),
            ]
        ),
    )
