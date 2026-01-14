constants = import_module("../package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")

TEST_RUNNER_IMAGE = "ghcr.io/agglayer/e2e:dda31ee"


def run(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
    l1_context,
    l2_context,
    agglayer_context,
):
    # Generate new wallet for the test runner.
    funder_private_key = args.get("l2_admin_private_key")
    wallet = _generate_new_funded_l1_l2_wallet(
        plan, funder_private_key, l1_context.rpc_url, l2_context.rpc_http_url
    )

    # Start the test runner.
    l2_bridge_address = _get_l2_bridge_address(
        plan,
        l2_context.sequencer_type,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
    )
    plan.add_service(
        name="test-runner" + l2_context.name,
        config=ServiceConfig(
            image=TEST_RUNNER_IMAGE,
            env_vars={
                # For now, we've only defined variables used by `tests/agglayer/bridges.bats`.
                # https://github.com/AggLayer/e2e/blob/main/tests/agglayer/bridges.bats
                # Agglayer and bridge.
                "AGGLAYER_RPC_URL": agglayer_context.rpc_url,
                "BRIDGE_SERVICE_URL": l2_context.zkevm_bridge_service_url,
                "CLAIMTXMANAGER_ADDR": args.get("l2_claimsponsor_address"),
                # L1.
                "L1_PRIVATE_KEY": wallet.private_key,
                "L1_RPC_URL": l1_context.rpc_url,
                "L1_BRIDGE_ADDR": contract_setup_addresses.get("l1_bridge_address"),
                # L2.
                "L2_PRIVATE_KEY": wallet.private_key,
                "L2_RPC_URL": l2_context.rpc_http_url,
                "L2_BRIDGE_ADDR": l2_bridge_address,
                # Other parameters.
                "CLAIM_WAIT_DURATION": "20m",  # default: 10m
                "TX_RECEIPT_TIMEOUT_SECONDS": "900",  # default: 60
            },
            entrypoint=["bash", "-c"],
            cmd=["sleep infinity"],
        ),
    )


def _get_l2_bridge_address(
    plan,
    sequencer_type,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
):
    if sequencer_type == constants.SEQUENCER_TYPE.op_geth:
        return sovereign_contract_setup_addresses.get("sovereign_bridge_proxy_addr")

    if "l2_bridge_address" in contract_setup_addresses:
        return contract_setup_addresses.get("l2_bridge_address")
    return contract_setup_addresses.get("l1_bridge_address")


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
