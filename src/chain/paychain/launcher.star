aggkit_package = import_module("../shared/aggkit.star")
constants = import_module("../../package_io/constants.star")
ports_package = import_module("../shared/ports.star")


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

    ports = {
        ports_package.HTTP_RPC_PORT_ID: PortSpec(
            ports_package.HTTP_RPC_PORT_NUMBER,
            application_protocol="http",
            wait=None,
        ),
        ports_package.PAYCHAIN_GRPC_PORT_ID: PortSpec(
            ports_package.PAYCHAIN_GRPC_PORT_NUMBER,
            application_protocol="grpc",
            wait=None,
        ),
    }

    plan.add_service(
        name=service_name,
        config=ServiceConfig(
            image=args["paychain_node_image"],
            ports=ports,
            entrypoint=["/usr/local/bin/paychain-node"],
            cmd=[
                "--rpc.addr=0.0.0.0:{}".format(ports_package.HTTP_RPC_PORT_NUMBER),
                "--grpc.addr=0.0.0.0:{}".format(ports_package.PAYCHAIN_GRPC_PORT_NUMBER),
                "--chain-id={}".format(args["l2_chain_id"]),
                "--block-time={}s".format(args.get("paychain_block_time", 1)),
                "--bridge-addr={}".format(
                    contract_setup_addresses.get("l2_bridge_address", "")
                ),
                "--ger-addr={}".format(
                    contract_setup_addresses.get("l2_ger_address", "")
                ),
                "--ger-updater-addr={}".format(args["l2_aggoracle_address"]),
                "--gas-token-enabled={}".format(args.get("gas_token_enabled", False)),
                "--gas-token-address={}".format(
                    args.get("gas_token_address", constants.ZERO_ADDRESS)
                ),
            ],
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
