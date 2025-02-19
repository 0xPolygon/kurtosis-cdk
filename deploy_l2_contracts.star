service_package = import_module("./lib/service.star")


def run(plan, args, deploy_l2_contracts):
    l2_rpc_url = service_package.get_l2_rpc_url(plan, args)

    # When funding accounts and deploying the contracts on l2, the
    # zkevm-contracts service is reused to reduce startup time. Since the l2
    # doesn't exist at the time the service is added to kurtosis, the
    # `l2_rpc_url` can't be templated. Therefore, the `l2_rpc_url` is exported
    # as an environment variable before running the `run-l2-contract-setup.sh`.

    plan.exec(
        description="Deploying contracts on L2",
        service_name="contracts" + args["deployment_suffix"],
        recipe=ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "export l2_rpc_url={0} && chmod +x {1} && {1} {2}".format(
                    l2_rpc_url.http,
                    "/opt/contract-deploy/run-l2-contract-setup.sh",
                    str(deploy_l2_contracts).strip().lower(),
                ),
            ]
        ),
    )
