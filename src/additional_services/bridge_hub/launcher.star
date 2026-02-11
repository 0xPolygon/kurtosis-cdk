api = import_module("./api.star")
proxy = import_module("./proxy.star")
server = import_module("./server.star")


def run(
    plan, args, contract_setup_addresses, l1_context, l2_context, deployment_stages
):
    api_url = api.run(plan, args, contract_setup_addresses, l2_context)

    l1_bridge_address = contract_setup_addresses.get("l1_bridge_address")
    web_ui_url = server.run(plan, args, contract_setup_addresses, l2_context, api_url)

    if deployment_stages.get("deploy_l1"):
        proxy.run(
            plan,
            args,
            l1_context.rpc_url,
            l2_context.rpc_url,
            api_url,
            web_ui_url,
        )
