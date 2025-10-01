def sanity_check(plan, args, op_args, source):
    # Run the optimism-package sanity check
    optimism_package_sanity_check_module = import_module(
        source.replace("main.star", "src/package_io/sanity_check.star")
    )
    optimism_package_sanity_check_module.sanity_check(plan, op_args)

    # Run additional sanity checks on the first OP chain
    check_first_chain_id(args, op_args)
    check_first_chain_name(args, op_args)
    check_first_chain_block_time(args, op_args)


def check_first_chain_id(args, op_args):
    chains = op_args.get("chains")
    if len(chains.keys()) == 0:
        fail("At least one OP chain must be defined")
    chain1 = chains["chain1"]
    network_params1 = chain1.get("network_params")
    op_chain_id = network_params1.get("network_id")

    zkevm_rollup_chain_id = args.get("zkevm_rollup_chain_id")
    if str(op_chain_id) != str(zkevm_rollup_chain_id):
        fail(
            "The chain id of the first OP chain does not match the zkevm rollup chain id"
        )


def check_first_chain_name(args, op_args):
    chains = op_args.get("chains")
    if len(chains.keys()) == 0:
        fail("At least one OP chain must be defined")
    chain1 = chains["chain1"]
    network_params1 = chain1.get("network_params")
    op_chain_name = network_params1.get("name")

    deployment_suffix_without_prefix = args.get("deployment_suffix")[1:]
    if op_chain_name != deployment_suffix_without_prefix:
        fail(
            "The name of the first OP chain does not match the deployment suffix without the leading suffix '-'"
        )


def check_first_chain_block_time(args, op_args):
    chains = op_args.get("chains")
    if len(chains.keys()) == 0:
        fail("At least one OP chain must be defined")
    chain1 = chains["chain1"]
    network_params1 = chain1.get("network_params")
    l2_block_time = network_params1.get("seconds_per_slot")

    l1_block_time = args.get("l1_seconds_per_slot")
    if l2_block_time > l1_block_time:
        fail(
            "The L2 block time of the first OP chain cannot be greater than the L1 block time"
        )
