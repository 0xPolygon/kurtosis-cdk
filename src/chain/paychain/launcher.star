aggkit_package = import_module("../shared/aggkit.star")
constants = import_module("../../package_io/constants.star")
ports_package = import_module("../shared/ports.star")


def genesis_alloc_flags(args):
    """The genesis-determining paychain-node flags: `--ger-updater` plus one
    `--alloc addr:balance` per genesis-funded account.

    These are the ONLY flags that affect paychain-node's height-0 (genesis)
    state root (see `genesis_state` in paychain-node/src/node.rs). Shared by
    `launch()` (the node runtime) and `paychain-node genesis-root` (invoked from
    contracts/agglayer.star to seed the AggchainPayments contract's initial
    `lastStateRoot`) so the contract's initial root is computed from EXACTLY the
    same inputs as the node's block-0 state root, by construction.
    """
    flags = ["--ger-updater", args["l2_aggoracle_address"]]
    genesis_balance = "1000000000000000000000000"
    for addr in [
        args.get("l2_admin_address"),
        args.get("l2_sequencer_address"),
        args.get("l2_aggoracle_address"),
        args.get("l2_sovereignadmin_address"),
        args.get("l2_claimsponsor_address"),
    ]:
        if addr:
            flags += ["--alloc", "{}:{}".format(addr, genesis_balance)]
    return flags


def launch(
    plan,
    args,
    contract_setup_addresses,
    sovereign_contract_setup_addresses,
    deployment_stages,
):
    """Deploy paychain-node, the only L2 service for the cdk-payments flavor.

    There is no geth/OP stack and no L2 genesis step: paychain-node implements
    the bridge/GER/ERC20 "contracts" as native virtual facades at fixed
    addresses mirroring the sovereign-genesis addresses, so it is configured
    directly off the L1-side contract_setup_addresses (AGGLAYER_PAYMENTS_v2.md §8).
    """
    service_name = args["l2_rpc_name"] + args["deployment_suffix"]

    # paychain-node computes the SP1 guest vkey (client.setup) at startup before
    # it binds RPC/gRPC — ~45-60s. Give the RPC port a generous readiness wait so
    # add_service blocks until the node is actually serving; otherwise downstream
    # consumers (zkevm-bridge-service, aggkit) start first and crash on a refused
    # connection to paychain-node:8545.
    ports = {
        ports_package.HTTP_RPC_PORT_ID: PortSpec(
            ports_package.HTTP_RPC_PORT_NUMBER,
            application_protocol="http",
            wait="180s",
        ),
        ports_package.PAYCHAIN_GRPC_PORT_ID: PortSpec(
            ports_package.PAYCHAIN_GRPC_PORT_NUMBER,
            application_protocol="grpc",
            wait="180s",
        ),
    }

    # paychain-node CLI (see paychain-node/src/main.rs): flags are `--name value`
    # (space-separated, not `--name=value`), the binary rejects unknown flags, and
    # there are no gas-token flags. Facade/GER addresses come from the L1-side
    # sovereign deploy (contract_setup_addresses); --ger-updater is the aggoracle
    # EOA that is permitted to call insertGlobalExitRoot on the GER facade.
    #
    # Note on facades: v2 spec's illustrative fixed addresses (bridge
    # 0x2a3D…2EDe, GER 0xa40D…b8fA) were standalone-genesis values; here the
    # node is configured directly off the sovereign deploy's l2_bridge_address /
    # l2_ger_address so the node facades, aggkit bridgesync, and the aggoracle
    # target all agree on the same addresses.
    seal_ms = int(args.get("paychain_block_time", 1) * 1000)
    cmd = [
        "--rpc",
        "0.0.0.0:{}".format(ports_package.HTTP_RPC_PORT_NUMBER),
        "--grpc",
        "0.0.0.0:{}".format(ports_package.PAYCHAIN_GRPC_PORT_NUMBER),
        "--data-dir",
        "/data",
        "--chain-id",
        str(args["l2_chain_id"]),
        "--network-id",
        str(args["l2_network_id"]),
        "--bridge",
        contract_setup_addresses.get("l2_bridge_address", ""),
        "--ger-manager",
        contract_setup_addresses.get("l2_ger_address", ""),
        "--seal-ms",
        str(seal_ms),
        "--prover-mode",
        "mock",
        "--metrics",
        "0.0.0.0:9100",
    ]

    # Genesis-determining flags: --ger-updater (the aggoracle EOA) plus one
    # --alloc per genesis-funded L2 account the demo transacts with (admin,
    # sequencer, aggoracle, sovereign admin, claim sponsor) so GER-injection,
    # autoclaims, and the bridge spammer all have balance (1e6 ether each).
    # Shared with the AggchainPayments genesis-root seeding (agglayer.star) via
    # genesis_alloc_flags() so the contract's initial lastStateRoot == the
    # node's block-0 state root by construction.
    cmd += genesis_alloc_flags(args)

    plan.add_service(
        name=service_name,
        config=ServiceConfig(
            image=args["paychain_node_image"],
            ports=ports,
            entrypoint=["/usr/local/bin/paychain-node"],
            cmd=cmd,
            # info-level so the unknown-method / unknown-selector WARNs
            # (target `paychain::rpc`) B4's compat discipline emits are visible
            # in `kurtosis service logs` for the M2 triage.
            env_vars={"RUST_LOG": "info"},
            files={
                "/data": Directory(
                    persistent_key="paychain-data" + args["deployment_suffix"]
                ),
            },
        ),
    )

    rpc_url = "http://{}:{}".format(service_name, ports_package.HTTP_RPC_PORT_NUMBER)

    plan.print("Deploying aggkit infrastructure")
    aggkit_bridge_url = aggkit_package.run(
        plan,
        args,
        contract_setup_addresses,
        sovereign_contract_setup_addresses,
        deployment_stages,
    )

    return struct(
        rpc_url=rpc_url,
        aggkit_bridge_url=aggkit_bridge_url,
    )
