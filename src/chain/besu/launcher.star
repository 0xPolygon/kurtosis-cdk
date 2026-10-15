aggkit_package = import_module("../shared/aggkit.star")
ports_package = import_module("../shared/ports.star")


# The Besu node itself is started earlier, from main.star, because the sovereign rollup has to be
# initialized against a running L2. This launcher only brings up the aggkit components that
# connect the chain to Agglayer, mirroring the op-reth launcher.
def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
):
    aggkit_bridge_url = aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deployment_stages,
    )

    return struct(
        rpc_url=args["l2_el_rpc_url"],
        aggkit_bridge_url=aggkit_bridge_url,
    )
