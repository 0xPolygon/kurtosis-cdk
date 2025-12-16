aggkit_package = import_module("../../../aggkit.star")
op_succinct_proposer = import_module("./op_succinct_proposer.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deploy_cdk_bridge_infra,
    deploy_op_succinct,
):
    # Deploy op-succinct-proposer
    if deploy_op_succinct:
        plan.print("Deploying op-succinct-proposer")
        op_succinct_proposer.run(plan, args | contract_setup_addresses)

    # Deploy aggkit infrastructure + dedicated bridge service
    plan.print("Deploying aggkit infrastructure")
    aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deploy_cdk_bridge_infra,
        deploy_op_succinct,
    )
