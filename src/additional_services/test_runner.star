hex = import_module("../hex/hex.star")
service_package = import_module("../../lib/service.star")
wallet_module = import_module("../wallet/wallet.star")

TEST_RUNNER_IMAGE = "leovct/e2e:be038b8"


def run(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deploy_optimism_rollup,
):
    # Get urls.
    l1_rpc_url = args.get("l1_rpc_url")
    l2_rpc_url = _get_l2_rpc_url(plan, args)
    bridge_service_url = _get_bridge_service_url(plan, args)
    l2_bridge_address = _get_l2_bridge_address(
        plan,
        deploy_optimism_rollup,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
    )

    # Generate new wallet for the test runner.
    funder_private_key = args.get("zkevm_l2_admin_private_key")
    wallet = _generate_new_funded_l1_l2_wallet(
        plan, funder_private_key, l1_rpc_url, l2_rpc_url
    )

    # Start the test runner.
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
                "L1_PRIVATE_KEY": wallet.private_key,
                "L1_RPC_URL": l1_rpc_url,
                "L1_BRIDGE_ADDR": contract_setup_addresses.get("zkevm_bridge_address"),
                # L2.
                "L2_PRIVATE_KEY": wallet.private_key,
                "L2_RPC_URL": l2_rpc_url,
                "L2_BRIDGE_ADDR": l2_bridge_address,
                # Other parameters.
                "CLAIM_WAIT_DURATION": "10m",  # default: 10m
                "TX_RECEIPT_TIMEOUT_SECONDS": "600",  # default: 60
            },
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
        ),
    )


def _get_l2_rpc_url(plan, args):
    service_name = args.get("l2_rpc_name") + args.get("deployment_suffix")
    service = plan.get_service(service_name)
    if "rpc" not in service.ports:
        fail("The 'rpc' port of the l2 rpc service is not available.")
    return service.ports["rpc"].url


def _get_bridge_service_url(plan, args):
    service_name = "zkevm-bridge-service" + args.get("deployment_suffix")
    service = plan.get_service(service_name)
    if "rpc" not in service.ports:
        fail("The 'rpc' port of the l2 rpc service is not available.")
    return service.ports["rpc"].url


def _get_l2_bridge_address(
    plan,
    deploy_optimism_rollup,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
):
    if deploy_optimism_rollup:
        return sovereign_contract_setup_addresses.get("sovereign_bridge_proxy_addr")

    if "zkevm_bridge_l2_address" in contract_setup_addresses:
        return contract_setup_addresses.get("zkevm_bridge_l2_address")
    return contract_setup_addresses.get("zkevm_bridge_address")


def _generate_new_funded_l1_l2_wallet(plan, funder_private_key, l1_rpc_url, l2_rpc_url):
    wallet = wallet_module.new(plan)
    wallet_module.fund(
        plan,
        address=wallet.address,
        rpc_url=l1_rpc_url,
        funder_private_key=funder_private_key,
    )
    wallet_module.fund(
        plan,
        address=wallet.address,
        rpc_url=l2_rpc_url,
        funder_private_key=funder_private_key,
    )
    return wallet
