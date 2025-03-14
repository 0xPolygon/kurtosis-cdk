def run(plan, args):
    service_name = "contracts" + args["deployment_suffix"]
    plan.exec(
        description="Creating sovereign predeployed Genesis for OP Stack",
        service_name=service_name,
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

    allocs_file = "predeployed_allocs.json"

    plan.store_service_files(
        service_name=service_name,
        name=allocs_file,
        src="/opt/zkevm/" + allocs_file,
        description="Storing {}".format(allocs_file),
    )
