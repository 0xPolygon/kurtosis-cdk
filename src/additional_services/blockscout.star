blockscout_package = import_module(
    "github.com/xavier-romero/kurtosis-blockscout/main.star"
)
service_package = import_module("../../lib/service.star")


FRONTEND_PORT_NUMBER = 3000


def run(plan, args):
    l2_rpc_urls = service_package.get_l2_rpc_urls(plan, args)
    blockscout_package.run(
        plan,
        args={
            "blockscout_public_port": FRONTEND_PORT_NUMBER,
            "rpc_url": l2_rpc_urls.http,
            "trace_url": l2_rpc_urls.http,
            "ws_url": l2_rpc_urls.ws,
            "chain_id": str(args["zkevm_rollup_chain_id"]),
            "deployment_suffix": args["deployment_suffix"],
        },
    )
