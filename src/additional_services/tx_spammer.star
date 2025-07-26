constants = import_module("../../src/package_io/constants.star")
wallet_module = import_module("../wallet/wallet.star")

TX_SPAMMER_SCRIPT_PATH = "../../static_files/additional_services/tx-spammer/loadtest.sh"


def run(plan, args):
    # Get rpc urls and funder private keys.
    l1_rpc_url = args.get("l1_rpc_url")
    l2_rpc_url = _get_l2_rpc_url(plan, args)
    l1_funder_private_key = args.get("l1_preallocated_private_key")
    l2_funder_private_key = args.get("zkevm_l2_admin_private_key")

    # Start the spammer services.
    tx_spammer_artifact = plan.upload_files(
        src=TX_SPAMMER_SCRIPT_PATH,
        name="tx-spammer-script",
    )

    l1_tx_spammer_wallet = _generate_new_funded_wallet(
        plan, l1_funder_private_key, l1_rpc_url
    )
    _start_tx_spammer_service(
        plan,
        name="l1-tx-spammer" + args.get("deployment_suffix"),
        script_artifact=tx_spammer_artifact,
        private_key=l1_tx_spammer_wallet.private_key,
        rpc_url=l1_rpc_url,
    )

    l2_tx_spammer_wallet = _generate_new_funded_wallet(
        plan, l2_funder_private_key, l2_rpc_url
    )
    _start_tx_spammer_service(
        plan,
        name="l2-tx-spammer" + args.get("deployment_suffix"),
        script_artifact=tx_spammer_artifact,
        private_key=l2_tx_spammer_wallet.private_key,
        rpc_url=l2_rpc_url,
    )


def _get_l2_rpc_url(plan, args):
    service_name = args.get("l2_rpc_name") + args.get("deployment_suffix")
    service = plan.get_service(service_name)
    if "rpc" not in service.ports:
        fail("The 'rpc' port of the l2 rpc service is not available.")
    return service.ports["rpc"].url


def _generate_new_funded_wallet(plan, funder_private_key, rpc_url):
    wallet = wallet_module.new(plan)
    wallet_module.fund(
        plan,
        address=wallet.address,
        rpc_url=rpc_url,
        funder_private_key=funder_private_key,
    )
    return wallet


def _start_tx_spammer_service(plan, name, script_artifact, private_key, rpc_url):
    plan.add_service(
        name=name,
        config=ServiceConfig(
            image=constants.TOOLBOX_IMAGE,
            files={
                "/opt": Directory(artifact_names=[script_artifact]),
            },
            env_vars={
                "PRIVATE_KEY": private_key,
                "RPC_URL": rpc_url,
            },
            entrypoint=["bash", "-c"],
            cmd=["chmod +x /opt/{1} && /opt/{1}".format(TX_SPAMMER_SCRIPT_NAME)],
        ),
    )
