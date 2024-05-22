blockscout_package = import_module(
    "github.com/xavier-romero/kurtosis-blockscout/main.star"
)


def run(plan, args):
    rpc_url = None
    ws_url = None
    for service in plan.get_services():
        if service.name == "zkevm-node-rpc" + args["deployment_suffix"]:
            rpc_url = "http://{}:{}".format(
                service.ip_address, service.ports["http-rpc"].number
            )
            ws_url = "ws://{}:{}".format(
                service.ip_address, service.ports["ws-rpc"].number
            )
            break

    if not (rpc_url and ws_url):
        fail("Could not find the zkevm-node-rpc service")

    # Start blockscout.
    blockscout_package.run(
        plan,
        args={
            "blockscout_public_port": args["blockscout_public_port"],
            "rpc_url": rpc_url,
            "trace_url": rpc_url,
            "ws_url": ws_url,
            "chain_id": str(args["zkevm_rollup_chain_id"]),
            "deployment_suffix": args["deployment_suffix"],
        },
    )
