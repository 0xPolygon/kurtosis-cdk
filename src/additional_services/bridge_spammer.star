constants = import_module("../../src/package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")


BRIDGE_SPAMMER_SCRIPT_FILE_PATH = (
    "../../static_files/additional_services/bridge-spammer-config/spam.sh"
)


def run(plan, args, contract_setup_addresses):
    # Get rpc urls.
    l1_rpc_url = args.get("l1_rpc_url")
    l2_rpc_url = _get_l2_rpc_url(plan, args)

    # Generate new wallet for the bridge spammer.
    funder_private_key = args.get("zkevm_l2_admin_private_key")
    wallet = _generate_new_funded_wallet(
        plan, funder_private_key, l1_rpc_url, l2_rpc_url
    )

    # Start the bridge spammer.
    bridge_spammer_config_artifact = plan.upload_files(
        src=BRIDGE_SPAMMER_SCRIPT_FILE_PATH,
        name="bridge-spammer-script",
    )
    plan.add_service(
        name="bridge-spammer" + args["deployment_suffix"],
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                "/opt/scripts": Directory(
                    artifact_names=[bridge_spammer_config_artifact]
                ),
            },
            env_vars={
                "PRIVATE_KEY": wallet.private_key,
                # rpc urls and chain ids
                "L1_CHAIN_ID": args.get("l1_chain_id"),
                "L1_RPC_URL": l1_rpc_url,
                "L2_CHAIN_ID": args.get("zkevm_rollup_chain_id"),
                "L2_RPC_URL": l2_rpc_url,
                # addresses
                "L2_CLAIM_TX_MANAGER_ADDRESS": args.get(
                    "zkevm_l2_claimtxmanager_address"
                ),
                "L1_BRIDGE_ADDRESS": contract_setup_addresses.get(
                    "zkevm_bridge_address"
                ),
                "L2_BRIDGE_ADDRESS": contract_setup_addresses.get(
                    "zkevm_bridge_l2_address"
                ),
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /opt/scripts/spam.sh && /opt/scripts/spam.sh"],
        ),
    )


def _get_l2_rpc_url(plan, args):
    service_name = args.get("l2_rpc_name") + args.get("deployment_suffix")
    service = plan.get_service(service_name)
    return service.get("rpc")


def _generate_new_funded_wallet(plan, funder_private_key, l1_rpc_url, l2_rpc_url):
    # Generate a new wallet and fund it on L1 and L2.
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
