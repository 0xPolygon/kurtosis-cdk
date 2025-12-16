aggkit_package = import_module("../../../aggkit.star")
op_succinct = import_module("./op_succinct.star")


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
        op_succinct.run(plan, args | contract_setup_addresses)

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
