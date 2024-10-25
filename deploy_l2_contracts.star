service_package = import_module("./lib/service.star")

def run(plan, args):
    l2_rpc_url = service_package.get_l2_rpc_url(plan, args)

    plan.exec(
        description="Deploying contracts on L2",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "export l2_rpc_url={0} && chmod +x {1} && {1}".format(
                    l2_rpc_url.http,
                    "/opt/contract-deploy/run-l2-contract-setup.sh",
                ),
            ]
        ),
    )
