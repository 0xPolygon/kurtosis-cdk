def sanity_check(plan, args, op_args, source):
    # Run the optimism-package sanity check
    optimism_package_sanity_check_module = import_module(
        source.replace("main.star", "src/package_io/sanity_check.star")
    )
    optimism_package_sanity_check_module.sanity_check(plan, op_args)

    # Run additional sanity checks on the first OP chain
    check_first_chain_id(args, op_args)
    check_first_chain_block_time(args, op_args)


def check_first_chain_id(args, op_args):
    chains = op_args.get("chains")
    if len(chains.keys()) == 0:
        fail("At least one OP chain must be defined")

    chain1_name = chains.keys()[0]
    chain1 = chains[chain1_name]
    if not "network_params" in chain1:
        fail("The first OP chain must define network_params")
    if not "network_id" in chain1["network_params"]:
        fail("The first OP chain's network_params must define network_id")
    chain1_id = chain1["network_params"]["network_id"]

    zkevm_rollup_chain_id = args.get("zkevm_rollup_chain_id")
    if str(chain1_id) != str(zkevm_rollup_chain_id):
        fail(
            "The chain id of the first OP chain does not match the zkevm rollup chain id"
        )


def check_first_chain_block_time(args, op_args):
    chains = op_args.get("chains")
    if len(chains.keys()) == 0:
        fail("At least one OP chain must be defined")

    chain1_name = chains.keys()[0]
    chain1 = chains[chain1_name]
    if not "network_params" in chain1:
        fail("The first OP chain must define network_params")
    if not "seconds_per_slot" in chain1["network_params"]:
        fail("The first OP chain's network_params must define seconds_per_slot")
    chain1_block_time = chain1["network_params"]["seconds_per_slot"]

    l1_block_time = args.get("l1_seconds_per_slot")
    if chain1_block_time > l1_block_time:
        fail(
            "The L2 block time of the first OP chain cannot be greater than the L1 block time"
        )
