cdk_erigon_package = import_module("../../lib/cdk_erigon.star")
zkevm_prover_package = import_module("../../lib/zkevm_prover.star")


def run(plan, args, genesis_artifact):
    # Start stateless executor if needed.
    if args["erigon_strict_mode"]:
        stateless_executor_config_template = read_file(
            src="./templates/trusted-node/prover-config.json"
        )
        stateless_executor_config_artifact = plan.render_templates(
            name="stateless-executor-config-artifact",
            config={
                "stateless-executor-config.json": struct(
                    template=stateless_executor_config_template,
                    data=args | {"stateless_executor": True},
                )
            },
        )
        zkevm_prover_package.start_stateless_executor(
            plan, args, stateless_executor_config_artifact
        )

    # Start cdk-erigon RPC.
    cdk_erigon_package.start_rpc(plan, args)
