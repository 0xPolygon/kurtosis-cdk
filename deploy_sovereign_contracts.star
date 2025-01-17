def run(plan, args):
    plan.exec(
        description="Deploying sovereign contracts on OP Stack",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "chmod +x {0} && {0}".format(
                    "/opt/contract-deploy/run-sovereign-setup.sh"
                ),
            ]
        ),
    )
