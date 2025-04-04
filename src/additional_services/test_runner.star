hex = import_module("../hex/hex.star")
service_package = import_module("../../lib/service.star")

TEST_RUNNER_IMAGE = "leovct/e2e:3fe0718"  # https://github.com/agglayer/e2e/pull/37


def run(plan, args, contract_setup_addresses):
    l1_rpc_url = args.get("mitm_rpc_url").get("agglayer", args.get("l1_rpc_url"))

    # Note: Getting values this way is not clean at all!!!
    bridge_service_url = ""
    l2_rpc_url = ""
    l2_bridge_address = ""
    if args.get("deploy_optimism_rollup"):
        # Bridge service url.
        bridge_service_name = "sovereign-bridge-service{}".format(
            args.get("deployment_suffix")
        )
        bridge_service = plan.get_service(bridge_service_name)
        bridge_service_url = "http://{}:{}".format(
            bridge_service.name,
            bridge_service.ports.get("rpc").number,
        )

        # L2 rpc url.
        op_el_rpc_name = "op-el-1-op-geth-op-node{}".format(
            args.get("deployment_suffix")
        )
        op_el_rpc_service = plan.get_service(op_el_rpc_name)
        l2_rpc_url = "http://{}:{}".format(
            op_el_rpc_service.name,
            op_el_rpc_service.ports.get("rpc").number,
        )

        # L2 bridge contract address.
        l2_bridge_address = contract_setup_addresses.get("sovereign_bridge_proxy_addr")
    else:
        # Bridge service url.
        bridge_service_name = "zkevm-bridge-service{}".format(
            args.get("deployment_suffix")
        )
        bridge_service = plan.get_service(bridge_service_name)
        bridge_service_url = "http://{}:{}".format(
            bridge_service.name,
            bridge_service.ports.get("rpc").number,
        )

        # L2 rpc url.
        l2_rpc_url = service_package.get_l2_rpc_url(plan, args).http

        # 2L bridge contract address.
        l2_bridge_address = contract_setup_addresses.get("zkevm_bridge_l2_address")

    l1_private_key = hex.normalize(args.get("zkevm_l2_admin_private_key"))
    l2_private_key = hex.normalize(
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    )
    plan.add_service(
        name="test-runner",
        config=ServiceConfig(
            image=TEST_RUNNER_IMAGE,
            env_vars={
                # For now, we've only defined variables used by `tests/agglayer/bridges.bats`.
                # https://github.com/agglayer/e2e/blob/jhilliard/gas-token-test/tests/agglayer/bridges.bats
                # Agglayer and bridge.
                "AGGLAYER_RPC_URL": args.get("agglayer_readrpc_url"),
                "BRIDGE_SERVICE_URL": bridge_service_url,
                "CLAIMTXMANAGER_ADDR": args.get("zkevm_l2_claimtxmanager_address"),
                # L1.
                "L1_PRIVATE_KEY": l1_private_key,
                "L1_RPC_URL": l1_rpc_url,
                "L1_BRIDGE_ADDR": contract_setup_addresses.get("zkevm_bridge_address"),
                # L2.
                "L2_PRIVATE_KEY": l2_private_key,
                "L2_RPC_URL": l2_rpc_url,
                "L2_BRIDGE_ADDR": l2_bridge_address,
            },
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
        ),
    )
