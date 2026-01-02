aggkit_package = import_module("../shared/aggkit.star")
op_succinct_proposer = import_module("./op_succinct_proposer.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deploy_cdk_bridge_infra,
    deploy_op_succinct,
):
    if deploy_op_succinct:
        op_succinct_proposer.run(plan, args | contract_setup_addresses)

    aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deploy_cdk_bridge_infra,
        deploy_op_succinct,
    )
