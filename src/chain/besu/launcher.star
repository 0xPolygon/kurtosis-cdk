aggkit_package = import_module("../shared/aggkit.star")
aggkit_prover_qbft = import_module("../shared/aggkit_prover_qbft.star")
constants = import_module("../../package_io/constants.star")
ports_package = import_module("../shared/ports.star")


# The Besu node itself is started earlier, from main.star, because the sovereign rollup has to be
# initialized against a running L2. This launcher only brings up the aggkit components that
# connect the chain to Agglayer, mirroring the op-reth launcher. For consensus_contract_type 'qbft'
# that includes aggkit-prover-qbft, which needs the initialized AggchainQBFT and is started before
# aggkit so the aggsender finds it.
def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
):
    if args["consensus_contract_type"] == constants.CONSENSUS_TYPE.qbft:
        aggkit_prover_qbft.run(
            plan, args, contract_setup_addresses, sovereign_contract_setup_addresses
        )

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
