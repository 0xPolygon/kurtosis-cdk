blockscout_package = import_module(
    "github.com/xavier-romero/kurtosis-blockscout/main.star@9de7765a6c98c8c357f747ff953fdbc0e39ebc3d"
)
contracts_util = import_module("./src/contracts/util.star")


def run(plan, args):
    l2_rpc_url = contracts_util.get_l2_rpc_url(plan, args)

    blockscout_params = {
        "rpc_url": l2_rpc_url.http,
        "trace_url": l2_rpc_url.http,
        "ws_url": l2_rpc_url.ws,
        "chain_id": str(args["zkevm_rollup_chain_id"]),
        "deployment_suffix": args["deployment_suffix"],
    } | args.get("blockscout_params", {})

    blockscout_package.run(plan, args=blockscout_params)
