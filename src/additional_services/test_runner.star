service_package = import_module("../../lib/service.star")

TEST_RUNNER_IMAGE = "leovct/e2e:3fe0718"  # https://github.com/agglayer/e2e/pull/37


def run(plan, args, contract_setup_addresses):
    private_key = args.get("zkevm_l2_admin_private_key")

    # Note: Getting values this way is not clean at all.
    agglayer_rpc_url = args.get("agglayer_readrpc_url")
    bridge_service = plan.get_service(
        name="zkevm-bridge-service" + args.get("deployment_suffix")
    )
    bridge_service_url = "http://{}:{}".format(
        bridge_service.name,
        bridge_service.ports.get("rpc").number,
    )

    l1_rpc_url = args.get("mitm_rpc_url").get("agglayer", args.get("l1_rpc_url"))
    l1_bridge_address = contract_setup_addresses.get("zkevm_bridge_address")

    l2_rpc_url = service_package.get_l2_rpc_url(plan, args).http
    l2_bridge_address = contract_setup_addresses.get("zkevm_bridge_l2_address")

    plan.add_service(
        name="test-runner",
        config=ServiceConfig(
            image=TEST_RUNNER_IMAGE,
            env_vars={
                # For now, we've only defined variables used by `tests/agglayer/bridges.bats`.
                # https://github.com/agglayer/e2e/blob/jhilliard/gas-token-test/tests/agglayer/bridges.bats
                # Agglayer and bridge.
                "AGGLAYER_RPC_URL": agglayer_rpc_url,
                "BRIDGE_SERVICE_URL": bridge_service_url,
                "CLAIMTXMANAGER_ADDR": args.get("zkevm_l2_claimtxmanager_address"),
                # L1.
                "L1_PRIVATE_KEY": private_key,
                "L1_RPC_URL": l1_rpc_url,
                "L1_BRIDGE_ADDR": l1_bridge_address,
                # L2.
                "L2_PRIVATE_KEY": private_key,
                "L2_RPC_URL": l2_rpc_url,
                "L2_BRIDGE_ADDR": l2_bridge_address,
            },
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
        ),
    )
