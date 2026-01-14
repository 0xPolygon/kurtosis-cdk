blockscout_package = import_module(
    "github.com/xavier-romero/kurtosis-blockscout/main.star@9de7765a6c98c8c357f747ff953fdbc0e39ebc3d"
)


def run(plan, args, l2_context):
    blockscout_params = {
        "rpc_url": l2_context.rpc_http_url,
        "trace_url": l2_context.rpc_http_url,
        "ws_url": l2_context.rpc_ws_url,
        "chain_id": l2_context.chain_id,
        "deployment_suffix": l2_context.name,
    } | args.get("blockscout_params", {})
    blockscout_package.run(plan, blockscout_params)
