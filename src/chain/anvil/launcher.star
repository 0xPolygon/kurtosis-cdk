aggkit_package = import_module("../shared/aggkit.star")
constants = import_module("../../package_io/constants.star")
ports_package = import_module("../shared/ports.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
):
    """Deploy the aggkit stack on top of an already-running anvil L2.

    The anvil node itself is started earlier, from main.star, because
    initialize_rollup needs a live L2. This mirrors op-reth, where the
    optimism-package likewise starts the chain before this point.
    """
    aggkit_bridge_url = aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deployment_stages,
    )

    rpc_url = "http://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.HTTP_RPC_PORT_NUMBER,
    )
    return struct(
        rpc_url=rpc_url,
        aggkit_bridge_url=aggkit_bridge_url,
    )
