blockscout_package = import_module(
    "github.com/xavier-romero/kurtosis-blockscout/main.star"
)


FRONTEND_PORT_NUMBER = 3000

def run(plan, args):
    zkevm_node_rpc_service = plan.get_service(
        name="zkevm-node-rpc" + args["deployment_suffix"]
    )
    zkevm_node_rpc_http_url = "http://{}:{}".format(
        zkevm_node_rpc_service.ip_address,
        zkevm_node_rpc_service.ports["http-rpc"].number,
    )
    zkevm_node_rpc_ws_url = "http://{}:{}".format(
        zkevm_node_rpc_service.ip_address, zkevm_node_rpc_service.ports["ws-rpc"].number
    )

    blockscout_package.run(
        plan,
        args={
            "blockscout_public_port": FRONTEND_PORT_NUMBER,
            "rpc_url": zkevm_node_rpc_http_url,
            "trace_url": zkevm_node_rpc_http_url,
            "ws_url": zkevm_node_rpc_ws_url,
            "chain_id": str(args["zkevm_rollup_chain_id"]),
            "deployment_suffix": args["deployment_suffix"],
        },
    )
