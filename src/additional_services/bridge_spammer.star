constants = import_module("../../src/package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")

# The folder where bridge spammer template files are stored in the repository.
TEMPLATES_FOLDER_PATH = "../../static_files/additional_services/bridge-spammer"
# The name of the bridge spammer script.
SCRIPT_NAME = "bridge.sh"

# The folder where bridge spammer scripts are stored inside the service.
SCRIPT_FOLDER_PATH = constants.SCRIPTS_DIR


def run(plan, args, contract_setup_addresses, l1_context, l2_context):
    # Generate new wallet for the bridge spammer.
    funder_private_key = args.get("l2_admin_private_key")
    wallet = _generate_new_funded_l1_l2_wallet(
        plan, funder_private_key, l1_context.el_rpc_url, l2_context.rpc_http_url
    )

    # Fund the l2 claim tx manager address.
    wallet_module.fund(
        plan,
        address=args.get("l2_claimsponsor_address"),
        rpc_url=l2_context.rpc_http_url,
        funder_private_key=funder_private_key,
        value="50ether",
    )

    # Start the bridge spammer.
    bridge_spammer_config_artifact = plan.upload_files(
        src="{}/{}".format(TEMPLATES_FOLDER_PATH, SCRIPT_NAME),
        name="bridge-spammer-script" + l2_context.name,
    )
    plan.add_service(
        name="bridge-spammer" + l2_context.name,
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                SCRIPT_FOLDER_PATH: Directory(
                    artifact_names=[bridge_spammer_config_artifact]
                ),
            },
            env_vars={
                "PRIVATE_KEY": wallet.private_key,
                # l1
                "L1_CHAIN_ID": l1_context.chain_id,
                "L1_RPC_URL": l1_context.el_rpc_url,
                # l2
                "L2_NETWORK_ID": str(l2_context.network_id),
                "L2_CHAIN_ID": str(l2_context.chain_id),
                "L2_RPC_URL": l2_context.rpc_http_url,
                # addresses
                "L1_BRIDGE_ADDRESS": contract_setup_addresses.get("l1_bridge_address"),
                "L2_BRIDGE_ADDRESS": contract_setup_addresses.get("l2_bridge_address"),
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x {0}/{1} && {0}/{1}".format(SCRIPT_FOLDER_PATH, SCRIPT_NAME)],
        ),
    )


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
