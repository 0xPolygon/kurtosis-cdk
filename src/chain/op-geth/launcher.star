aggkit_package = import_module("../shared/aggkit.star")
op_succinct_proposer = import_module("./op_succinct_proposer.star")
ports_package = import_module("../shared/ports.star")
zkevm_bridge_service = import_module("../shared/zkevm_bridge_service.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deploy_op_succinct,
):
    if deploy_op_succinct:
        op_succinct_proposer.run(plan, args | contract_setup_addresses)

    # zkevm-bridge-service (legacy)
    l2_rpc_url = "http://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.HTTP_RPC_PORT_NUMBER,
    )
    zkevm_bridge_service.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        l2_rpc_url,
    )

    aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deploy_op_succinct,
    )

    return struct(
        rpc_url=None,
        bridge_service_url=None,
    )
