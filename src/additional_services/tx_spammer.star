constants = import_module("../../src/package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")

# The folder where tx spammer template files are stored in the repository.
TEMPLATES_FOLDER_PATH = "../../static_files/additional_services/tx-spammer"
# The name of the tx spammer script.
SCRIPT_NAME = "spam.sh"

# The folder where tx spammer scripts are stored inside the service.
SCRIPT_FOLDER_PATH = "/opt/scripts"


def run(plan, args, contract_setup_addresses):
    # Get rpc urls.
    l2_rpc_url = _get_l2_rpc_url(plan, args)

    # Generate new wallet for the tx spammer.
    funder_private_key = args.get("zkevm_l2_admin_private_key")
    wallet = _generate_new_funded_l1_wallet(plan, funder_private_key, l2_rpc_url)

    # Start the tx spammer.
    tx_spammer_config_artifact = plan.upload_files(
        src="{}/{}".format(TEMPLATES_FOLDER_PATH, SCRIPT_NAME),
        name="tx-spammer-script",
    )
    plan.add_service(
        name="tx-spammer" + args.get("deployment_suffix"),
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                SCRIPT_FOLDER_PATH: Directory(
                    artifact_names=[tx_spammer_config_artifact]
                ),
            },
            env_vars={
                "PRIVATE_KEY": wallet.private_key,
                "RPC_URL": l2_rpc_url,
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x {0}/{1} && {0}/{1}".format(SCRIPT_FOLDER_PATH, SCRIPT_NAME)],
        ),
    )


def _get_l2_rpc_url(plan, args):
    service_name = args.get("l2_rpc_name") + args.get("deployment_suffix")
    service = plan.get_service(service_name)
    if "rpc" not in service.ports:
        fail("The 'rpc' port of the l2 rpc service is not available.")
    return service.ports["rpc"].url


def _generate_new_funded_l1_wallet(plan, funder_private_key, l2_rpc_url):
    wallet = wallet_module.new(plan)
    wallet_module.fund(
        plan,
        address=wallet.address,
        rpc_url=l2_rpc_url,
        funder_private_key=funder_private_key,
    )
    return wallet
