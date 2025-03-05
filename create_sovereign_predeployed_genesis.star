def run(plan, args):
    plan.exec(
        description="Creating sovereign predeployed Genesis for OP Stack",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format(
                    "/opt/contract-deploy/create-predeployed-sovereign-genesis.sh"
                ),
            ]
        ),
    )
