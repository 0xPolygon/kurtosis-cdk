aggkit_package = import_module("../shared/aggkit.star")
op_succinct_proposer = import_module("./op_succinct_proposer.star")
ports_package = import_module("../shared/ports.star")


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
):
    deploy_op_succinct = deployment_stages.get("deploy_op_succinct", False)
    if deploy_op_succinct:
        op_succinct_proposer.run(plan, args | contract_setup_addresses)

    aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deployment_stages,
    )

    # TODO: Derive the rpc url from the optimism package instead
    rpc_http_url = "http://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.HTTP_RPC_PORT_NUMBER,
    )
    rpc_ws_url = "ws://{}{}:{}".format(
        args.get("l2_rpc_name"),
        args.get("deployment_suffix"),
        ports_package.WS_RPC_PORT_NUMBER,
    )
    return struct(
        rpc_http_url=rpc_http_url,
        rpc_ws_url=rpc_ws_url,
    )
